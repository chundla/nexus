#if os(macOS)
import Darwin
import Foundation
import NexusDomain
import NexusIPC

public protocol NexusEmbeddedServiceSession: AnyObject {
    var listenerEndpoint: NSXPCListenerEndpoint { get }
    var storeURL: URL { get }
}

public enum NexusEmbeddedServiceBootstrap {
    public static func bootstrap() throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrap()
    }

    public static func bootstrapForTests() throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrapForTests()
    }

    public static func bootstrapForTests(rootURL: URL) throws -> any NexusEmbeddedServiceSession {
        try NexusService.bootstrapForTests(rootURL: rootURL)
    }
}

protocol SessionRuntimeManaging: AnyObject {
    func setRuntimeChangeHandler(_ handler: (@Sendable (UUID) -> Void)?)
    func launchOrResume(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) async throws
    func stop(session: Session) throws
    func remove(session: Session)
    func hasRuntime(for session: Session) -> Bool
    func runtimeState(for session: Session) -> Session.State?
    func sessionRecordAdapterMetadata(for session: Session) -> SessionRecordAdapterMetadata?
    func sessionScreen(for session: Session) throws -> SessionScreen
    func addUpdateObserver(id: UUID, for session: Session, observer: @escaping @Sendable () -> Void)
    func removeUpdateObserver(id: UUID)
    func sendInput(_ text: String, to session: Session) throws -> SessionScreen
    func sendText(_ text: String, to session: Session) throws -> SessionScreen
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision, to session: Session) throws -> SessionScreen
    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen
}

enum RemoteRuntimeLaunchMode {
    case launchNew
    case attachExisting
}

private enum SessionRecordAdapterMetadataLaunchSource {
    case stored
    case explicit(SessionRecordAdapterMetadata?)
}

struct SessionRuntimeLaunchConfiguration {
    let executable: String
    let arguments: [String]
    let workingDirectory: String
    let remoteHost: NexusDomain.Host?
    let remoteRuntimeIdentifier: String?
    let remoteRuntimeLaunchMode: RemoteRuntimeLaunchMode
    let sessionRecordAdapterMetadata: SessionRecordAdapterMetadata?
    let initialTranscript: String
    let terminationStatusMessageBuilder: (Int32) -> String

    init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: String,
        remoteHost: NexusDomain.Host?,
        remoteRuntimeIdentifier: String? = nil,
        remoteRuntimeLaunchMode: RemoteRuntimeLaunchMode = .launchNew,
        sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? = nil,
        initialTranscript: String = "",
        terminationStatusMessageBuilder: @escaping (Int32) -> String = { _ in "" }
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.remoteHost = remoteHost
        self.remoteRuntimeIdentifier = remoteRuntimeIdentifier
        self.remoteRuntimeLaunchMode = remoteRuntimeLaunchMode
        self.sessionRecordAdapterMetadata = sessionRecordAdapterMetadata
        self.initialTranscript = initialTranscript
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder
    }
}

protocol SessionRuntimeLaunching {
    func makeRuntime(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) async throws -> any SessionRuntime
}

protocol SessionRuntime: AnyObject {
    var state: Session.State { get }
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? { get }
    func sessionScreen(for session: Session) -> SessionScreen
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)
    func stop() throws
    func sendInput(_ text: String) throws
    func sendText(_ text: String) throws
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws
    func resize(columns: Int, rows: Int) throws
}

final class SessionControllerRegistry: @unchecked Sendable {
    private struct Record {
        var controller: SessionController = .mac
        var lastKnownMacSize: (columns: Int, rows: Int)?
    }

    private let lock = NSLock()
    private var records: [UUID: Record] = [:]

    func controller(for sessionID: UUID) -> SessionController {
        lock.lock()
        defer { lock.unlock() }
        return records[sessionID]?.controller ?? .mac
    }

    func takeRemoteControl(sessionID: UUID, pairedDeviceID: UUID, currentMacSize: (columns: Int, rows: Int)) {
        lock.lock()
        var record = records[sessionID] ?? Record()
        if record.lastKnownMacSize == nil {
            record.lastKnownMacSize = currentMacSize
        }
        record.controller = .pairedDevice(pairedDeviceID)
        records[sessionID] = record
        lock.unlock()
    }

    func isRemoteController(sessionID: UUID, pairedDeviceID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return records[sessionID]?.controller == .pairedDevice(pairedDeviceID)
    }

    func releaseRemoteControl(sessionID: UUID, pairedDeviceID: UUID) -> (columns: Int, rows: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard records[sessionID]?.controller == .pairedDevice(pairedDeviceID) else {
            return nil
        }

        var record = records[sessionID] ?? Record()
        record.controller = .mac
        records[sessionID] = record
        return record.lastKnownMacSize
    }

    func claimMacControl(sessionID: UUID, preferredSize: (columns: Int, rows: Int)? = nil) -> (columns: Int, rows: Int)? {
        lock.lock()
        defer { lock.unlock() }
        var record = records[sessionID] ?? Record()
        if let preferredSize {
            record.lastKnownMacSize = preferredSize
        }
        record.controller = .mac
        records[sessionID] = record
        return record.lastKnownMacSize
    }
}

enum NexusSessionControlError: LocalizedError {
    case remoteControllerRequired
    case remoteSessionInputControllerRequired
    case remoteApprovalRequestControllerRequired

    var errorDescription: String? {
        switch self {
        case .remoteControllerRequired:
            "Take Controller on this iPhone before sending terminal input."
        case .remoteSessionInputControllerRequired:
            "Take Controller on this iPhone before sending Session input."
        case .remoteApprovalRequestControllerRequired:
            "Take Controller on this iPhone before responding to Approval Requests."
        }
    }
}

enum NexusSessionApprovalError: LocalizedError {
    case approvalRequestsUnavailable

    var errorDescription: String? {
        switch self {
        case .approvalRequestsUnavailable:
            "This Session does not have app-native approval requests."
        }
    }
}

final class InMemorySessionRuntimeManager: SessionRuntimeManaging, @unchecked Sendable {
    private let launcher: any SessionRuntimeLaunching
    private let lock = NSLock()
    private var runtimes: [UUID: any SessionRuntime] = [:]
    private var updateObservers: [UUID: [UUID: @Sendable () -> Void]] = [:]
    private var observedSessionIDs: [UUID: UUID] = [:]
    private var runtimeChangeHandler: (@Sendable (UUID) -> Void)?

    init(launcher: any SessionRuntimeLaunching = ProcessSessionRuntimeLauncher()) {
        self.launcher = launcher
    }

    func setRuntimeChangeHandler(_ handler: (@Sendable (UUID) -> Void)?) {
        lock.lock()
        runtimeChangeHandler = handler
        lock.unlock()
    }

    func launchOrResume(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) async throws {
        let shouldCreateRuntime = try withLock {
            if let runtime = runtimes[session.id], runtime.state == .ready {
                return false
            }
            return true
        }

        guard shouldCreateRuntime else {
            return
        }

        let runtime = try await launcher.makeRuntime(session: session, workspace: workspace, launchConfiguration: launchConfiguration)
        runtime.setChangeHandler { [weak self] in
            self?.notifyRuntimeChange(for: session.id)
        }

        try withLock {
            runtimes[session.id] = runtime
        }
        notifyRuntimeChange(for: session.id)
    }

    func stop(session: Session) throws {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.stop()
        notifyRuntimeChange(for: session.id)
    }

    func remove(session: Session) {
        lock.lock()
        runtimes.removeValue(forKey: session.id)?.setChangeHandler(nil)
        updateObservers.removeValue(forKey: session.id)
        observedSessionIDs = observedSessionIDs.filter { $0.value != session.id }
        lock.unlock()
    }

    func hasRuntime(for session: Session) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id] != nil
    }

    func runtimeState(for session: Session) -> Session.State? {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id]?.state
    }

    func sessionRecordAdapterMetadata(for session: Session) -> SessionRecordAdapterMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return runtimes[session.id]?.sessionRecordAdapterMetadata
    }

    func sessionScreen(for session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        return runtime.sessionScreen(for: session)
    }

    func addUpdateObserver(id observationID: UUID, for session: Session, observer: @escaping @Sendable () -> Void) {
        lock.lock()
        updateObservers[session.id, default: [:]][observationID] = observer
        observedSessionIDs[observationID] = session.id
        lock.unlock()
    }

    func removeUpdateObserver(id: UUID) {
        lock.lock()
        guard let sessionID = observedSessionIDs.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        updateObservers[sessionID]?.removeValue(forKey: id)
        if updateObservers[sessionID]?.isEmpty == true {
            updateObservers.removeValue(forKey: sessionID)
        }
        lock.unlock()
    }

    func sendInput(_ text: String, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.sendInput(text)
        return runtime.sessionScreen(for: session)
    }

    func sendText(_ text: String, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.sendText(text)
        return runtime.sessionScreen(for: session)
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.sendInputKey(key, applicationCursorMode: applicationCursorMode)
        return runtime.sessionScreen(for: session)
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision, to session: Session) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.respondToApprovalRequest(approvalRequestID, decision: decision)
        return runtime.sessionScreen(for: session)
    }

    func resize(session: Session, columns: Int, rows: Int) throws -> SessionScreen {
        let runtime = try withLock {
            guard let runtime = runtimes[session.id] else {
                throw NexusMetadataStoreError.sessionNotFound
            }
            return runtime
        }

        try runtime.resize(columns: columns, rows: rows)
        return runtime.sessionScreen(for: session)
    }

    private func notifyRuntimeChange(for sessionID: UUID) {
        let runtimeChangeHandler: (@Sendable (UUID) -> Void)?
        let observers: [@Sendable () -> Void]
        lock.lock()
        runtimeChangeHandler = self.runtimeChangeHandler
        observers = Array(updateObservers[sessionID, default: [:]].values)
        lock.unlock()

        runtimeChangeHandler?(sessionID)
        for observer in observers {
            observer()
        }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

struct RemoteSessionCommandBuilder {
    func launchArguments(configuration: SessionRuntimeLaunchConfiguration) -> [String] {
        guard let host = configuration.remoteHost,
              let runtimeIdentifier = configuration.remoteRuntimeIdentifier else {
            return []
        }

        var arguments = [
            "-tt",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [
            host.sshTarget,
            "cd \(shellQuoted(configuration.workingDirectory)) && NEXUS_REMOTE_SHELL=\"$(\(remoteShellResolutionCommand()))\"; [ -n \"$NEXUS_REMOTE_SHELL\" ] || { echo 'NEXUS_REMOTE_SHELL_NOT_FOUND' >&2; exit 1; }; case \"${NEXUS_REMOTE_SHELL##*/}\" in csh|tcsh) exec tmux new-session -s \(shellQuoted(runtimeIdentifier)) \"$NEXUS_REMOTE_SHELL\" -i -c \(shellQuoted(cShellExecCommand(executable: configuration.executable, arguments: configuration.arguments))) ;; fish) exec tmux new-session -s \(shellQuoted(runtimeIdentifier)) \"$NEXUS_REMOTE_SHELL\" -i -c \(shellQuoted(shellExecCommand(executable: configuration.executable, arguments: configuration.arguments))) ;; *) exec tmux new-session -s \(shellQuoted(runtimeIdentifier)) \"$NEXUS_REMOTE_SHELL\" -lic \(shellQuoted(shellExecCommand(executable: configuration.executable, arguments: configuration.arguments))) ;; esac"
        ]
        return arguments
    }

    private func remoteShellResolutionCommand() -> String {
        "for shell in \(ShellSupport.remoteShellCandidateListScript()); do [ -n \"$shell\" ] || continue; [ -x \"$shell\" ] || continue; printf '%s' \"$shell\"; break; done"
    }

    private func shellExecCommand(executable: String, arguments: [String]) -> String {
        (["exec", shellQuoted(executable)] + arguments.map(shellQuoted)).joined(separator: " ")
    }

    private func cShellExecCommand(executable: String, arguments: [String]) -> String {
        "if ( -f ~/.login ) source ~/.login; \(shellExecCommand(executable: executable, arguments: arguments))"
    }

    func recoverArguments(configuration: SessionRuntimeLaunchConfiguration) -> [String] {
        guard let host = configuration.remoteHost,
              let runtimeIdentifier = configuration.remoteRuntimeIdentifier else {
            return []
        }

        var arguments = [
            "-tt",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [
            host.sshTarget,
            "tmux has-session -t \(shellQuoted(runtimeIdentifier)) 2>/dev/null || { echo 'NEXUS_REMOTE_RUNTIME_NOT_FOUND' >&2; exit 1; }; exec tmux attach-session -t \(shellQuoted(runtimeIdentifier))"
        ]
        return arguments
    }

    func stopArguments(runtimeIdentifier: String, host: NexusDomain.Host) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5"
        ]
        if let port = host.port {
            arguments += ["-p", String(port)]
        }
        arguments += [
            host.sshTarget,
            "tmux kill-session -t \(shellQuoted(runtimeIdentifier))"
        ]
        return arguments
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

final class ProcessSessionRuntimeLauncher: SessionRuntimeLaunching {
    typealias ProtocolNativeRuntimeFactory = (_ launchConfiguration: SessionRuntimeLaunchConfiguration, _ session: Session, _ workspace: Workspace) async throws -> any SessionRuntime

    private let remoteSessionCommandBuilder = RemoteSessionCommandBuilder()
    private let localShellCommandBuilder: LocalShellCommandBuilder
    private let localProtocolNativeRuntimeFactories: [ProviderID: ProtocolNativeRuntimeFactory]
    private let remoteProtocolNativeRuntimeFactories: [ProviderID: ProtocolNativeRuntimeFactory]

    init(
        localShellCommandBuilder: LocalShellCommandBuilder = LocalShellCommandBuilder(),
        piTransportFactory: PiRPCSessionRuntime.TransportFactory? = nil,
        codexTransportFactory: CodexAppServerRuntime.TransportFactory? = nil,
        ibmBobTransportFactory: IBMBobSessionRuntime.TransportFactory? = nil,
        localProtocolNativeRuntimeFactories: [ProviderID: ProtocolNativeRuntimeFactory]? = nil,
        remoteProtocolNativeRuntimeFactories: [ProviderID: ProtocolNativeRuntimeFactory] = [:],
        remoteProtocolSessionCommandBuilder: RemoteProtocolSessionCommandBuilder = RemoteProtocolSessionCommandBuilder(),
        remoteIBMBobCommandBuilder: RemoteIBMBobCommandBuilder = RemoteIBMBobCommandBuilder()
    ) {
        let resolvedPiTransportFactory: PiRPCSessionRuntime.TransportFactory = piTransportFactory ?? { executable, arguments, workingDirectory in
            try ProcessPiRPCTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }
        let resolvedCodexTransportFactory: CodexAppServerRuntime.TransportFactory = codexTransportFactory ?? { executable, arguments, workingDirectory in
            try ProcessCodexAppServerTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }

        self.localShellCommandBuilder = localShellCommandBuilder
        let resolvedIBMBobTransportFactory: IBMBobSessionRuntime.TransportFactory = ibmBobTransportFactory ?? { executable, arguments, workingDirectory in
            try ProcessIBMBobTransport(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }

        self.localProtocolNativeRuntimeFactories = localProtocolNativeRuntimeFactories ?? [
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
                    transportFactory: resolvedCodexTransportFactory
                )
            },
            .ibmBob: { launchConfiguration, _, _ in
                try IBMBobSessionRuntime(
                    executable: launchConfiguration.executable,
                    workingDirectory: launchConfiguration.workingDirectory,
                    sessionLinkage: launchConfiguration.sessionRecordAdapterMetadata?.ibmBobSessionLinkage,
                    terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder,
                    transportFactory: resolvedIBMBobTransportFactory
                )
            }
        ]

        if remoteProtocolNativeRuntimeFactories.isEmpty {
            self.remoteProtocolNativeRuntimeFactories = [
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
                            try Self.runCommand(
                                executable: "/usr/bin/ssh",
                                arguments: remoteProtocolSessionCommandBuilder.stopArguments(
                                    runtimeIdentifier: runtimeIdentifier,
                                    host: remoteHost
                                )
                            )
                        },
                        transportFactory: { _, _, _ in
                            try resolvedPiTransportFactory("/usr/bin/ssh", bridgeArguments, nil)
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
                            try Self.runCommand(
                                executable: "/usr/bin/ssh",
                                arguments: remoteProtocolSessionCommandBuilder.stopArguments(
                                    runtimeIdentifier: runtimeIdentifier,
                                    host: remoteHost
                                )
                            )
                        },
                        transportFactory: { _, _, _ in
                            try resolvedCodexTransportFactory("/usr/bin/ssh", bridgeArguments, nil)
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
                            try resolvedIBMBobTransportFactory(
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
        } else {
            self.remoteProtocolNativeRuntimeFactories = remoteProtocolNativeRuntimeFactories
        }
    }

    func makeRuntime(session: Session, workspace: Workspace, launchConfiguration: SessionRuntimeLaunchConfiguration) async throws -> any SessionRuntime {
        if launchConfiguration.remoteHost == nil,
           let protocolNativeRuntimeFactory = localProtocolNativeRuntimeFactories[session.providerID] {
            return try await protocolNativeRuntimeFactory(launchConfiguration, session, workspace)
        }

        if launchConfiguration.remoteHost != nil,
           let protocolNativeRuntimeFactory = remoteProtocolNativeRuntimeFactories[session.providerID] {
            return try await protocolNativeRuntimeFactory(launchConfiguration, session, workspace)
        }

        if let remoteHost = launchConfiguration.remoteHost,
           let runtimeIdentifier = launchConfiguration.remoteRuntimeIdentifier {
            let arguments: [String]
            switch launchConfiguration.remoteRuntimeLaunchMode {
            case .launchNew:
                arguments = remoteSessionCommandBuilder.launchArguments(configuration: launchConfiguration)
            case .attachExisting:
                arguments = remoteSessionCommandBuilder.recoverArguments(configuration: launchConfiguration)
            }

            return try ProcessSessionRuntime(
                executable: "/usr/bin/ssh",
                arguments: arguments,
                workingDirectory: nil,
                initialTranscript: launchConfiguration.initialTranscript,
                stopHandler: {
                    try Self.runCommand(
                        executable: "/usr/bin/ssh",
                        arguments: self.remoteSessionCommandBuilder.stopArguments(runtimeIdentifier: runtimeIdentifier, host: remoteHost)
                    )
                },
                terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder
            )
        }

        let localLaunchCommand = localShellCommandBuilder.launchCommand(
            for: launchConfiguration.executable,
            arguments: launchConfiguration.arguments
        )
        return try ProcessSessionRuntime(
            executable: localLaunchCommand.executable,
            arguments: localLaunchCommand.arguments,
            workingDirectory: launchConfiguration.workingDirectory,
            initialTranscript: launchConfiguration.initialTranscript,
            terminationStatusMessageBuilder: launchConfiguration.terminationStatusMessageBuilder
        )
    }

    private static func runCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = [stderr, stdout]
                .compactMap { $0 }
                .first(where: { $0.isEmpty == false }) ?? "Remote command failed"
            throw NSError(domain: "ProcessSessionRuntimeLauncher", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }
}

final class ProcessSessionRuntime: SessionRuntime, @unchecked Sendable {
    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        nil
    }

    private let pid: pid_t
    private let terminalHandle: FileHandle
    private let masterFileDescriptor: Int32
    private let readSource: DispatchSourceRead
    private let terminationSource: DispatchSourceProcess
    private let stopHandler: (() throws -> Void)?
    private let terminationStatusMessageBuilder: (Int32) -> String
    private let lock = NSLock()
    private var runtimeState: Session.State
    private var storage: String
    private var terminalOutputStorage: String
    private var pendingTerminalOutput: String
    private var columns: Int
    private var rows: Int
    private var utf8Decoder = UTF8StreamDecoder()
    private var changeHandler: (@Sendable () -> Void)?

    init(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        initialTranscript: String,
        stopHandler: (() throws -> Void)? = nil,
        terminationStatusMessageBuilder: @escaping (Int32) -> String = { status in
            "\n[Process exited with status \(status)]\n"
        }
    ) throws {
        self.runtimeState = .ready
        self.storage = initialTranscript
        self.terminalOutputStorage = ""
        self.pendingTerminalOutput = ""
        self.columns = 80
        self.rows = 24
        self.stopHandler = stopHandler
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder

        var masterFileDescriptor: Int32 = -1
        var initialWindowSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&masterFileDescriptor, nil, nil, &initialWindowSize)
        guard pid >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }

        if pid == 0 {
            if let workingDirectory {
                chdir(workingDirectory)
            }
            setenv("TERM", "xterm-256color", 1)
            var processArguments: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
            processArguments.append(nil)
            _ = executable.withCString { executablePath in
                execv(executablePath, &processArguments)
            }
            _exit(127)
        }

        self.pid = pid
        self.masterFileDescriptor = masterFileDescriptor
        self.terminalHandle = FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true)
        self.readSource = DispatchSource.makeReadSource(fileDescriptor: masterFileDescriptor, queue: .global())
        self.terminationSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())

        readSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            let estimatedBytes = max(Int(self.readSource.data), 1)
            var buffer = [UInt8](repeating: 0, count: estimatedBytes)
            let bytesRead = Darwin.read(self.masterFileDescriptor, &buffer, buffer.count)
            guard bytesRead > 0 else {
                return
            }

            let data = Data(buffer.prefix(bytesRead))
            let text = self.decodeTerminalText(data)
            guard text.isEmpty == false else {
                return
            }
            let queryResponses = self.cursorPositionReportResponses(for: text)
            self.append(text)
            self.appendTerminalOutput(text)
            self.sendTerminalResponses(queryResponses)
            self.notifyChange()
        }
        readSource.activate()

        terminationSource.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            var status: Int32 = 0
            _ = waitpid(self.pid, &status, 0)
            self.lock.lock()
            self.runtimeState = .exited
            self.lock.unlock()
            let trailingText = self.flushDecodedTerminalText()
            if trailingText.isEmpty == false {
                self.append(trailingText)
                self.appendTerminalOutput(trailingText)
            }
            self.append(self.terminationStatusMessageBuilder(status))
            self.readSource.cancel()
            self.terminationSource.cancel()
            self.notifyChange()
        }
        terminationSource.activate()
    }

    deinit {
        readSource.cancel()
        terminationSource.cancel()
    }

    var state: Session.State {
        lock.lock()
        defer { lock.unlock() }
        return runtimeState
    }

    private var terminalTranscript: String {
        lock.lock()
        defer { lock.unlock() }
        return terminalOutputStorage
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let transcript = storage
        let terminalColumns = columns
        let terminalRows = rows
        lock.unlock()

        return SessionScreen(
            session: session,
            transcript: transcript,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func stop() throws {
        guard state == .ready else {
            return
        }

        try stopHandler?()

        guard kill(pid, SIGTERM) == 0 || errno == ESRCH else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }

        lock.lock()
        runtimeState = .exited
        lock.unlock()
        notifyChange()
    }

    func sendInput(_ text: String) throws {
        if text.isEmpty {
            try sendInputKey(.enter, applicationCursorMode: false)
            return
        }

        let trimmed = text.trimmingCharacters(in: .newlines)
        guard trimmed.isEmpty == false else {
            return
        }

        append("\n> \(trimmed)\n")
        notifyChange()
        guard let data = "\(trimmed)\n".data(using: .utf8) else {
            return
        }
        terminalHandle.write(data)
    }

    func sendText(_ text: String) throws {
        guard text.isEmpty == false, let data = text.data(using: .utf8) else {
            return
        }
        terminalHandle.write(data)
    }

    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {
        let escapeSequence: String
        switch key {
        case .enter:
            escapeSequence = "\r"
        case .tab:
            escapeSequence = "\t"
        case .escape:
            escapeSequence = "\u{001B}"
        case .backspace:
            escapeSequence = "\u{007F}"
        case .deleteForward:
            escapeSequence = "\u{001B}[3~"
        case .endOfTransmission:
            escapeSequence = "\u{0004}"
        case .interrupt:
            escapeSequence = "\u{0003}"
        case .home:
            escapeSequence = applicationCursorMode ? "\u{001B}OH" : "\u{001B}[H"
        case .end:
            escapeSequence = applicationCursorMode ? "\u{001B}OF" : "\u{001B}[F"
        case .upArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OA" : "\u{001B}[A"
        case .downArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OB" : "\u{001B}[B"
        case .leftArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OD" : "\u{001B}[D"
        case .rightArrow:
            escapeSequence = applicationCursorMode ? "\u{001B}OC" : "\u{001B}[C"
        }

        guard let data = escapeSequence.data(using: .utf8) else {
            return
        }
        terminalHandle.write(data)
    }

    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {
        throw NexusSessionApprovalError.approvalRequestsUnavailable
    }

    func resize(columns: Int, rows: Int) throws {
        let clampedColumns = max(1, columns)
        let clampedRows = max(1, rows)

        var windowSize = winsize(ws_row: UInt16(clampedRows), ws_col: UInt16(clampedColumns), ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(masterFileDescriptor, TIOCSWINSZ, &windowSize) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }

        lock.lock()
        self.columns = clampedColumns
        self.rows = clampedRows
        lock.unlock()
        notifyChange()
    }

    private func cursorPositionReportResponses(for incomingText: String) -> [String] {
        let cprQueries = ["\u{001B}[6n", "\u{009B}6n"]
        let baseTranscript = terminalTranscript

        lock.lock()
        let columns = self.columns
        let rows = self.rows
        let priorTail = pendingTerminalOutput
        lock.unlock()

        let combinedText = priorTail + incomingText
        let pendingBoundary = combinedText.index(combinedText.startIndex, offsetBy: priorTail.count)
        var responses: [String] = []

        for query in cprQueries {
            var searchStart = combinedText.startIndex
            while let range = combinedText.range(of: query, range: searchStart..<combinedText.endIndex) {
                defer { searchStart = range.upperBound }
                guard range.upperBound > pendingBoundary else {
                    continue
                }

                let incomingCount = combinedText.distance(from: pendingBoundary, to: range.upperBound)
                let incomingEndIndex = incomingText.index(incomingText.startIndex, offsetBy: incomingCount)
                let transcriptPrefix = baseTranscript + String(incomingText[..<incomingEndIndex])
                let renderState = TerminalRenderer.renderState(
                    from: transcriptPrefix,
                    terminalColumns: columns,
                    terminalRows: rows
                )
                responses.append("\u{001B}[\(renderState.cursorRow + 1);\(renderState.cursorColumn + 1)R")
            }
        }

        lock.lock()
        pendingTerminalOutput = String(combinedText.suffix(3))
        lock.unlock()

        return responses
    }

    private func sendTerminalResponses(_ responses: [String]) {
        for response in responses {
            guard let data = response.data(using: .utf8) else {
                continue
            }
            terminalHandle.write(data)
        }
    }

    private func decodeTerminalText(_ data: Data) -> String {
        lock.lock()
        defer { lock.unlock() }
        return utf8Decoder.decode(data)
    }

    private func flushDecodedTerminalText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return utf8Decoder.finish()
    }

    private func append(_ text: String) {
        lock.lock()
        storage.append(text)
        lock.unlock()
    }

    private func appendTerminalOutput(_ text: String) {
        lock.lock()
        terminalOutputStorage.append(text)
        lock.unlock()
    }

    private func notifyChange() {
        let handler: (@Sendable () -> Void)?
        lock.lock()
        handler = changeHandler
        lock.unlock()
        handler?()
    }
}

final class IdleStructuredSessionRuntime: SessionRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var runtimeState: Session.State = .ready
    private var columns = 80
    private var rows = 24
    private var changeHandler: (@Sendable () -> Void)?
    private let activityItems: [SessionActivityItem]

    init(activityItems: [SessionActivityItem]) {
        self.activityItems = activityItems
    }

    var state: Session.State {
        lock.lock()
        defer { lock.unlock() }
        return runtimeState
    }

    var sessionRecordAdapterMetadata: SessionRecordAdapterMetadata? {
        nil
    }

    func sessionScreen(for session: Session) -> SessionScreen {
        lock.lock()
        let terminalColumns = columns
        let terminalRows = rows
        let state = runtimeState
        lock.unlock()

        return SessionScreen(
            session: Session(
                id: session.id,
                workspaceID: session.workspaceID,
                providerID: session.providerID,
                name: session.name,
                isDefault: session.isDefault,
                state: state,
                failureMessage: session.failureMessage
            ),
            primarySurface: .structuredActivityFeed,
            transcript: "",
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            activityItems: activityItems
        )
    }

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    func stop() throws {
        lock.lock()
        runtimeState = .exited
        let handler = changeHandler
        lock.unlock()
        handler?()
    }

    func sendInput(_ text: String) throws {}
    func sendText(_ text: String) throws {}
    func sendInputKey(_ key: SessionInputKey, applicationCursorMode: Bool) throws {}
    func respondToApprovalRequest(_ approvalRequestID: UUID, decision: ApprovalRequestDecision) throws {}

    func resize(columns: Int, rows: Int) throws {
        lock.lock()
        self.columns = columns
        self.rows = rows
        let handler = changeHandler
        lock.unlock()
        handler?()
    }
}

struct RemoteRuntimeRecoveryFailureContext {
    let detail: String
    let normalizedDetail: String
    let runtimeIdentifier: String
    let hostName: String

    var isMissingRemoteRuntime: Bool {
        normalizedDetail.contains("nexus_remote_runtime_not_found") || normalizedDetail.contains("can't find session")
    }
}

struct ServiceProviderAdapter {
    let provider: Provider
    private let defaultSessionLaunchSupportEvaluator: (Workspace) -> Bool
    private let namedSessionSupportEvaluator: (Workspace) -> Bool
    private let primarySurfaceEvaluator: (Workspace) -> SessionSurface
    let healthSummaryEvaluator: (Workspace, RemoteWorkspaceHealthContext?, any ProviderHealthEvaluating) async -> ProviderHealthSummary
    let initialTranscriptBuilder: (Workspace, NexusDomain.Host?, RemoteRuntimeLaunchMode) -> String
    let terminationStatusMessageBuilder: (Int32) -> String
    let remoteRuntimeRecoveryFailureEvaluator: (RemoteRuntimeRecoveryFailureContext) -> (state: Session.State, message: String)
    let shouldReuseRemoteHealthSnapshot: (ProviderHealthSummary, RemoteWorkspaceHealthContext?) -> Bool

    init(
        providerID: ProviderID,
        supportsDefaultSessionLaunch: Bool,
        supportsNamedSessions: Bool,
        healthSummaryEvaluator: @escaping (Workspace, RemoteWorkspaceHealthContext?, any ProviderHealthEvaluating) async -> ProviderHealthSummary,
        defaultSessionLaunchSupportEvaluator: ((Workspace) -> Bool)? = nil,
        namedSessionSupportEvaluator: ((Workspace) -> Bool)? = nil,
        primarySurfaceEvaluator: ((Workspace) -> SessionSurface)? = nil,
        initialTranscriptBuilder: ((Workspace, NexusDomain.Host?, RemoteRuntimeLaunchMode) -> String)? = nil,
        terminationStatusMessageBuilder: ((Int32) -> String)? = nil,
        remoteRuntimeRecoveryFailureEvaluator: ((RemoteRuntimeRecoveryFailureContext) -> (state: Session.State, message: String))? = nil,
        shouldReuseRemoteHealthSnapshot: @escaping (ProviderHealthSummary, RemoteWorkspaceHealthContext?) -> Bool = { _, _ in false }
    ) {
        let provider = Provider(id: providerID)
        self.provider = provider
        self.defaultSessionLaunchSupportEvaluator = defaultSessionLaunchSupportEvaluator ?? { _ in supportsDefaultSessionLaunch }
        self.namedSessionSupportEvaluator = namedSessionSupportEvaluator ?? { _ in supportsNamedSessions }
        self.primarySurfaceEvaluator = primarySurfaceEvaluator ?? { _ in .terminal }
        self.healthSummaryEvaluator = healthSummaryEvaluator
        self.initialTranscriptBuilder = initialTranscriptBuilder ?? { workspace, remoteHost, launchMode in
            if let remoteHost {
                switch launchMode {
                case .launchNew:
                    return "Connecting to \(workspace.name) on \(remoteHost.name) with \(provider.displayName)…\n"
                case .attachExisting:
                    return "Reconnecting to \(workspace.name) on \(remoteHost.name) with \(provider.displayName)…\n"
                }
            }

            return "Launching \(workspace.name) with \(provider.displayName)…\n"
        }
        self.terminationStatusMessageBuilder = terminationStatusMessageBuilder ?? { status in
            "\n[\(provider.displayName) exited with status \(status)]\n"
        }
        self.remoteRuntimeRecoveryFailureEvaluator = remoteRuntimeRecoveryFailureEvaluator ?? { context in
            if context.isMissingRemoteRuntime {
                return (
                    state: .failed,
                    message: "Known remote runtime '\(context.runtimeIdentifier)' is no longer available on \(context.hostName). Relaunch to create a new remote runtime."
                )
            }

            if context.normalizedDetail.contains("could not resolve hostname")
                || context.normalizedDetail.contains("operation timed out")
                || context.normalizedDetail.contains("connection refused")
                || context.normalizedDetail.contains("no route to host")
                || context.normalizedDetail.contains("connection closed by remote host")
                || context.normalizedDetail.contains("permission denied") {
                let suffix = context.detail.isEmpty ? "" : " \(context.detail)"
                return (
                    state: .interrupted,
                    message: "Could not reach \(context.hostName) to recover remote runtime '\(context.runtimeIdentifier)'.\(suffix)"
                )
            }

            let suffix = context.detail.isEmpty ? "" : " \(context.detail)"
            return (
                state: .interrupted,
                message: "Could not recover remote runtime '\(context.runtimeIdentifier)' on \(context.hostName).\(suffix)"
            )
        }
        self.shouldReuseRemoteHealthSnapshot = shouldReuseRemoteHealthSnapshot
    }

    func supportsDefaultSessionLaunch(in workspace: Workspace) -> Bool {
        defaultSessionLaunchSupportEvaluator(workspace)
    }

    func supportsNamedSessions(in workspace: Workspace) -> Bool {
        namedSessionSupportEvaluator(workspace)
    }

    func primarySurface(in workspace: Workspace) -> SessionSurface {
        primarySurfaceEvaluator(workspace)
    }

    func healthSummary(
        for workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        providerHealthEvaluator: any ProviderHealthEvaluating
    ) async -> ProviderHealthSummary {
        await healthSummaryEvaluator(workspace, remoteContext, providerHealthEvaluator)
    }

    func initialTranscript(
        for workspace: Workspace,
        remoteHost: NexusDomain.Host?,
        launchMode: RemoteRuntimeLaunchMode
    ) -> String {
        initialTranscriptBuilder(workspace, remoteHost, launchMode)
    }

    func terminationStatusMessage(for status: Int32) -> String {
        terminationStatusMessageBuilder(status)
    }

    func remoteRuntimeRecoveryFailure(
        for context: RemoteRuntimeRecoveryFailureContext
    ) -> (state: Session.State, message: String) {
        remoteRuntimeRecoveryFailureEvaluator(context)
    }
}

public final class NexusService: NSObject, NexusEmbeddedServiceSession, @unchecked Sendable {
    public let listener: NSXPCListener
    public let storeURL: URL

    public var listenerEndpoint: NSXPCListenerEndpoint {
        listener.endpoint
    }

    private let metadataStore: NexusMetadataStore
    private let providerHealthEvaluator: any ProviderHealthEvaluating
    private let hostValidationEvaluator: any HostValidationEvaluating
    private let workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating
    private let sessionRuntimeManager: any SessionRuntimeManaging
    private let remoteAccessRuntime: RemoteAccessRuntime
    private let ibmBobNativeSessionCleaner: any IBMBobNativeSessionCleaning
    private let providerAdapters: [ProviderID: ServiceProviderAdapter]
    private let sessionControllerRegistry = SessionControllerRegistry()

    private init(
        listener: NSXPCListener,
        storeURL: URL,
        metadataStore: NexusMetadataStore,
        providerHealthEvaluator: any ProviderHealthEvaluating,
        hostValidationEvaluator: any HostValidationEvaluating,
        workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating,
        sessionRuntimeManager: any SessionRuntimeManaging,
        remoteAccessRuntime: RemoteAccessRuntime,
        ibmBobNativeSessionCleaner: any IBMBobNativeSessionCleaning,
        providerAdapters: [ProviderID: ServiceProviderAdapter]
    ) {
        self.listener = listener
        self.storeURL = storeURL
        self.metadataStore = metadataStore
        self.providerHealthEvaluator = providerHealthEvaluator
        self.hostValidationEvaluator = hostValidationEvaluator
        self.workspaceAvailabilityEvaluator = workspaceAvailabilityEvaluator
        self.sessionRuntimeManager = sessionRuntimeManager
        self.remoteAccessRuntime = remoteAccessRuntime
        self.ibmBobNativeSessionCleaner = ibmBobNativeSessionCleaner
        self.providerAdapters = providerAdapters
        super.init()
        self.sessionRuntimeManager.setRuntimeChangeHandler { [weak self] sessionID in
            self?.persistRuntimeLinkageAfterRuntimeChange(sessionID: sessionID)
            self?.persistSessionStateAfterRuntimeChange(sessionID: sessionID)
        }
        self.listener.delegate = self
        self.listener.resume()
    }

    public static func bootstrap() throws -> NexusService {
        let rootURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Nexus", isDirectory: true)

        return try bootstrap(rootURL: rootURL)
    }

    public static func bootstrapForTests() throws -> NexusService {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return try bootstrap(rootURL: rootURL)
    }

    public static func bootstrapForTests(rootURL: URL) throws -> NexusService {
        try bootstrap(rootURL: rootURL)
    }

    static func bootstrapForTests(
        rootURL: URL,
        providerHealthEvaluator: any ProviderHealthEvaluating,
        hostValidationEvaluator: any HostValidationEvaluating = HostValidationEvaluator(),
        workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating = WorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: any SessionRuntimeManaging = InMemorySessionRuntimeManager(),
        remoteAccessRuntime: RemoteAccessRuntime = RemoteAccessRuntime(),
        providerAdapters: [ProviderID: ServiceProviderAdapter]? = nil,
        ibmBobNativeSessionCleaner: any IBMBobNativeSessionCleaning = IBMBobNativeSessionCleaner()
    ) throws -> NexusService {
        try bootstrap(
            rootURL: rootURL,
            providerHealthEvaluator: providerHealthEvaluator,
            hostValidationEvaluator: hostValidationEvaluator,
            workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
            sessionRuntimeManager: sessionRuntimeManager,
            remoteAccessRuntime: remoteAccessRuntime,
            providerAdapters: providerAdapters,
            ibmBobNativeSessionCleaner: ibmBobNativeSessionCleaner
        )
    }

    static func bootstrapForTests(
        rootURL: URL,
        hostValidationEvaluator: any HostValidationEvaluating,
        workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating = WorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: any SessionRuntimeManaging = InMemorySessionRuntimeManager(),
        remoteAccessRuntime: RemoteAccessRuntime = RemoteAccessRuntime(),
        ibmBobNativeSessionCleaner: any IBMBobNativeSessionCleaning = IBMBobNativeSessionCleaner()
    ) throws -> NexusService {
        try bootstrap(
            rootURL: rootURL,
            hostValidationEvaluator: hostValidationEvaluator,
            workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
            sessionRuntimeManager: sessionRuntimeManager,
            remoteAccessRuntime: remoteAccessRuntime,
            ibmBobNativeSessionCleaner: ibmBobNativeSessionCleaner
        )
    }

    private static func bootstrap(
        rootURL: URL,
        providerHealthEvaluator: any ProviderHealthEvaluating = ProviderHealthEvaluator(),
        hostValidationEvaluator: any HostValidationEvaluating = HostValidationEvaluator(),
        workspaceAvailabilityEvaluator: any WorkspaceAvailabilityEvaluating = WorkspaceAvailabilityEvaluator(),
        sessionRuntimeManager: any SessionRuntimeManaging = InMemorySessionRuntimeManager(),
        remoteAccessRuntime: RemoteAccessRuntime = RemoteAccessRuntime(),
        providerAdapters: [ProviderID: ServiceProviderAdapter]? = nil,
        ibmBobNativeSessionCleaner: any IBMBobNativeSessionCleaning = IBMBobNativeSessionCleaner()
    ) throws -> NexusService {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let storeURL = rootURL.appendingPathComponent("Nexus.sqlite", isDirectory: false)
        if FileManager.default.fileExists(atPath: storeURL.path) == false {
            FileManager.default.createFile(atPath: storeURL.path, contents: Data())
        }

        let metadataStore = try NexusMetadataStore(storeURL: storeURL)
        remoteAccessRuntime.restore(isEnabled: try metadataStore.remoteAccessEnabled())
        return NexusService(
            listener: NSXPCListener.anonymous(),
            storeURL: storeURL,
            metadataStore: metadataStore,
            providerHealthEvaluator: providerHealthEvaluator,
            hostValidationEvaluator: hostValidationEvaluator,
            workspaceAvailabilityEvaluator: workspaceAvailabilityEvaluator,
            sessionRuntimeManager: sessionRuntimeManager,
            remoteAccessRuntime: remoteAccessRuntime,
            ibmBobNativeSessionCleaner: ibmBobNativeSessionCleaner,
            providerAdapters: defaultProviderAdapters(overrides: providerAdapters)
        )
    }

    private static func shouldReuseRemoteCLIHealthSnapshot(
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
        case .unavailable, .misconfigured, .notChecked:
            return false
        case .blocked:
            return false
        }
    }

    private static func defaultProviderAdapters(
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
                supportsDefaultSessionLaunch: true,
                supportsNamedSessions: true,
                healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                    await providerHealthEvaluator.healthSummary(for: .pi, workspace: workspace, remoteContext: remoteContext)
                },
                primarySurfaceEvaluator: { _ in .structuredActivityFeed },
                shouldReuseRemoteHealthSnapshot: { snapshot, remoteContext in
                    shouldReuseRemoteCLIHealthSnapshot(snapshot, remoteContext: remoteContext)
                }
            )
        ]

        guard let overrides else {
            return defaults
        }

        return defaults.merging(overrides) { _, override in override }
    }

    public func serviceStatus() -> NexusServiceStatus {
        NexusServiceStatus(
            state: .running,
            store: .init(
                kind: .sqlite,
                owner: .backgroundService,
                location: storeURL
            )
        )
    }

    func listWorkspaceGroups() throws -> [WorkspaceGroup] {
        try metadataStore.listWorkspaceGroups()
    }

    func createWorkspaceGroup(name: String) throws -> WorkspaceGroup {
        try metadataStore.createWorkspaceGroup(name: name)
    }

    func listWorkspaces() throws -> [Workspace] {
        try metadataStore.listWorkspaces()
    }

    func listHosts() throws -> [NexusDomain.Host] {
        try metadataStore.listHosts()
    }

    func getHostDetail(hostID: UUID) throws -> NexusDomain.HostDetail {
        guard let host = try metadataStore.host(id: hostID) else {
            throw NexusMetadataStoreError.hostNotFound
        }

        return NexusDomain.HostDetail(host: host, latestValidation: try metadataStore.hostValidation(hostID: hostID))
    }

    func createHost(name: String, sshTarget: String, port: Int?) throws -> NexusDomain.Host {
        try metadataStore.createHost(name: name, sshTarget: sshTarget, port: port)
    }

    func updateHost(hostID: UUID, name: String, sshTarget: String, port: Int?) throws -> NexusDomain.Host {
        try metadataStore.updateHost(id: hostID, name: name, sshTarget: sshTarget, port: port)
    }

    func validateHost(hostID: UUID) throws -> HostValidationSnapshot {
        guard let host = try metadataStore.host(id: hostID) else {
            throw NexusMetadataStoreError.hostNotFound
        }

        return try metadataStore.saveHostValidation(
            hostID: hostID,
            result: hostValidationEvaluator.validate(host: host),
            checkedAt: Date()
        )
    }

    func deleteHost(hostID: UUID) throws -> Bool {
        try metadataStore.deleteHost(id: hostID)
    }

    func listRecentNavigation(limit: Int) throws -> [NavigationItem] {
        try metadataStore.listRecentNavigation(limit: limit).compactMap(navigationItem)
    }

    func remoteAccessState() -> RemoteAccessState {
        remoteAccessRuntime.state()
    }

    func setRemoteAccessEnabled(_ isEnabled: Bool) -> RemoteAccessState {
        let state = remoteAccessRuntime.setEnabled(isEnabled)
        try? metadataStore.setRemoteAccessEnabled(isEnabled)
        return state
    }

    func startPairing() throws -> PairingCeremony {
        try remoteAccessRuntime.startPairing()
    }

    func completePairing(pairingCode: String, deviceName: String) throws -> PairedDevice {
        try remoteAccessRuntime.completePairing(code: pairingCode)
        return try metadataStore.createPairedDevice(name: deviceName, pairedAt: Date())
    }

    func listPairedDevices() throws -> [PairedDevice] {
        try metadataStore.listPairedDevices()
    }

    func revokePairedDevice(deviceID: UUID) throws -> Bool {
        try metadataStore.deletePairedDevice(id: deviceID)
    }

    func recordRemoteClientDiagnosticBreadcrumb(_ breadcrumb: RemoteClientDiagnosticBreadcrumb) throws {
        try metadataStore.recordRemoteClientDiagnosticBreadcrumb(breadcrumb)
    }

    func recordNavigation(target: NavigationTarget) throws {
        try metadataStore.recordNavigation(target: target)
    }

    func searchNavigation(query: String) throws -> [NavigationItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.isEmpty == false else {
            return []
        }

        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let workspaces = try metadataStore.listWorkspaces()
        let workspaceItems = try workspaces.compactMap { workspace -> NavigationItem? in
            let item = NavigationItem(
                target: .workspace(workspace.id),
                title: workspace.name,
                subtitle: try workspaceNavigationSubtitle(workspace)
            )
            return try itemMatchesAllTokens(tokens, fields: workspaceSearchFields(workspace)) ? item : nil
        }

        let providerItems = try workspaces.flatMap { workspace in
            try ProviderID.allCases.compactMap { providerID -> NavigationItem? in
                let item = NavigationItem(
                    target: .provider(workspaceID: workspace.id, providerID: providerID),
                    title: providerID.displayName,
                    subtitle: try providerNavigationSubtitle(workspace: workspace)
                )
                return try providerMatchesQuery(tokens: tokens, normalizedQuery: normalizedQuery, providerID: providerID, workspace: workspace) ? item : nil
            }
        }

        let sessionItems = try metadataStore.listAllSessions().compactMap { session -> NavigationItem? in
            guard let workspace = try metadataStore.workspace(id: session.workspaceID) else {
                return nil
            }

            let item = NavigationItem(
                target: .session(session.id),
                title: sessionNavigationTitle(session),
                subtitle: try sessionNavigationSubtitle(session: session, workspace: workspace)
            )
            return try sessionMatchesQuery(tokens: tokens, normalizedQuery: normalizedQuery, session: session, workspace: workspace) ? item : nil
        }

        return workspaceItems.sorted(by: navigationItemSort)
            + providerItems.sorted(by: navigationItemSort)
            + sessionItems.sorted(by: navigationItemSort)
    }

    func getWorkspaceOverview(workspaceID: UUID) throws -> WorkspaceOverview {
        try AsyncOperationSupport.blocking { try await self.getWorkspaceOverview(workspaceID: workspaceID) }
    }

    func getWorkspaceOverview(workspaceID: UUID) async throws -> WorkspaceOverview {
        guard let workspace = try metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        let remoteTarget = try remoteWorkspaceTargetOverview(for: workspace)
        let remoteContext = remoteTarget.map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }

        var providerCards: [WorkspaceProviderCard] = []
        for providerID in ProviderID.allCases {
            let health = try await providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
            let defaultSession = try metadataStore.defaultSession(workspaceID: workspaceID, providerID: providerID)
            providerCards.append(
                WorkspaceProviderCard(
                    provider: Provider(id: providerID),
                    health: health,
                    capabilities: providerCapabilities(for: providerID, workspace: workspace, health: health, defaultSession: defaultSession),
                    prelaunchPrimarySurface: providerAdapter(for: providerID).primarySurface(in: workspace),
                    defaultSession: try defaultSessionSummary(for: workspace, providerID: providerID),
                    alternateSessionCount: try metadataStore.listSessions(workspaceID: workspaceID, providerID: providerID)
                        .filter { $0.isDefault == false }
                        .count
                )
            )
        }

        return WorkspaceOverview(workspace: workspace, providerCards: providerCards, remoteTarget: remoteTarget)
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) throws -> ProviderDetail {
        try AsyncOperationSupport.blocking { try await self.getProviderDetail(workspaceID: workspaceID, providerID: providerID) }
    }

    func getProviderDetail(workspaceID: UUID, providerID: ProviderID) async throws -> ProviderDetail {
        guard let workspace = try metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        let remoteTarget = try remoteWorkspaceTargetOverview(for: workspace)
        let remoteContext = remoteTarget.map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }
        let sessions = try metadataStore.listSessions(workspaceID: workspaceID, providerID: providerID)
            .map(reconcileSessionRuntimeState)
        let health = try await providerHealthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
        let defaultSession = sessions.first(where: \.isDefault)

        return ProviderDetail(
            workspace: workspace,
            provider: Provider(id: providerID),
            health: health,
            capabilities: providerCapabilities(for: providerID, workspace: workspace, health: health, defaultSession: defaultSession),
            prelaunchPrimarySurface: providerAdapter(for: providerID).primarySurface(in: workspace),
            defaultSession: defaultSession,
            alternateSessions: sessions.filter { $0.isDefault == false && $0.state != .failed },
            failedSessions: sessions.filter { $0.isDefault == false && $0.state == .failed }
        )
    }

    private func remoteWorkspaceTargetOverview(
        for workspace: Workspace,
        refreshHostValidation: Bool = false
    ) throws -> RemoteWorkspaceTargetOverview? {
        guard workspace.kind == .remote,
              let hostID = workspace.remoteHostID,
              let host = try metadataStore.host(id: hostID) else {
            return nil
        }

        let existingHostValidation = try metadataStore.hostValidation(hostID: hostID)
        let hostValidation: HostValidationSnapshot?
        if refreshHostValidation {
            hostValidation = try metadataStore.saveHostValidation(
                hostID: hostID,
                result: hostValidationEvaluator.validate(host: host),
                checkedAt: Date()
            )
        } else {
            hostValidation = existingHostValidation
        }

        let availabilityResult = workspaceAvailabilityEvaluator.evaluate(
            workspace: workspace,
            host: host,
            hostValidation: hostValidation
        )
        let availability = try metadataStore.saveWorkspaceAvailability(
            workspaceID: workspace.id,
            result: availabilityResult,
            checkedAt: Date()
        )
        return RemoteWorkspaceTargetOverview(
            host: host,
            hostValidation: hostValidation,
            workspaceAvailability: availability
        )
    }

    private func providerHealthSummary(
        for providerID: ProviderID,
        workspace: Workspace,
        remoteContext: RemoteWorkspaceHealthContext?,
        preferFreshRemoteCheck: Bool = false
    ) async throws -> ProviderHealthSummary {
        let adapter = providerAdapter(for: providerID)

        guard workspace.kind == .remote else {
            return await adapter.healthSummary(
                for: workspace,
                remoteContext: remoteContext,
                providerHealthEvaluator: providerHealthEvaluator
            )
        }

        if preferFreshRemoteCheck == false,
           let snapshot = try metadataStore.providerHealth(workspaceID: workspace.id, providerID: providerID),
           adapter.shouldReuseRemoteHealthSnapshot(snapshot, remoteContext) {
            return snapshot
        }

        let evaluated = await adapter.healthSummary(
            for: workspace,
            remoteContext: remoteContext,
            providerHealthEvaluator: providerHealthEvaluator
        )
        return try metadataStore.saveProviderHealth(
            workspaceID: workspace.id,
            providerID: providerID,
            summary: evaluated,
            checkedAt: Date()
        )
    }

    private func providerAdapter(for providerID: ProviderID) -> ServiceProviderAdapter {
        providerAdapters[providerID] ?? ServiceProviderAdapter(
            providerID: providerID,
            supportsDefaultSessionLaunch: false,
            supportsNamedSessions: false,
            healthSummaryEvaluator: { workspace, remoteContext, providerHealthEvaluator in
                await providerHealthEvaluator.healthSummary(for: providerID, workspace: workspace, remoteContext: remoteContext)
            }
        )
    }

    private func providerCapabilities(
        for providerID: ProviderID,
        workspace: Workspace,
        health: ProviderHealthSummary,
        defaultSession: Session?
    ) -> ProviderCapabilities {
        let adapter = providerAdapter(for: providerID)
        let supportsDefaultSessionLaunch = adapter.supportsDefaultSessionLaunch(in: workspace)
        let supportsNamedSessions = adapter.supportsNamedSessions(in: workspace)
        let canLaunchDefaultSession = supportsDefaultSessionLaunch && (defaultSession != nil || health.launchability == .launchable)
        let canCreateNamedSession = supportsNamedSessions && health.launchability == .launchable

        return ProviderCapabilities(
            launchDefaultSession: ProviderCapability(
                action: .launchDefaultSession,
                isSupported: supportsDefaultSessionLaunch,
                isEnabled: canLaunchDefaultSession,
                disabledReason: providerCapabilityDisabledReason(
                    action: .launchDefaultSession,
                    provider: adapter.provider,
                    isSupported: supportsDefaultSessionLaunch,
                    health: health,
                    isEnabled: canLaunchDefaultSession
                )
            ),
            createNamedSession: ProviderCapability(
                action: .createNamedSession,
                isSupported: supportsNamedSessions,
                isEnabled: canCreateNamedSession,
                disabledReason: providerCapabilityDisabledReason(
                    action: .createNamedSession,
                    provider: adapter.provider,
                    isSupported: supportsNamedSessions,
                    health: health,
                    isEnabled: canCreateNamedSession
                )
            )
        )
    }

    private func providerCapabilityDisabledReason(
        action: ProviderCapability.Action,
        provider: Provider,
        isSupported: Bool,
        health: ProviderHealthSummary,
        isEnabled: Bool
    ) -> String? {
        guard isEnabled == false else {
            return nil
        }

        guard isSupported else {
            switch action {
            case .launchDefaultSession:
                return "\(provider.displayName) cannot launch a Default Session on this Workspace yet."
            case .createNamedSession:
                return "\(provider.displayName) cannot create Named Sessions on this Workspace yet."
            }
        }

        return health.summary
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: UUID?) throws -> Workspace {
        try metadataStore.createLocalWorkspace(name: name, folderPath: folderPath, primaryGroupID: primaryGroupID)
    }

    func createRemoteWorkspace(name: String?, hostID: UUID, remotePath: String, primaryGroupID: UUID?) throws -> Workspace {
        try metadataStore.createRemoteWorkspace(name: name, hostID: hostID, remotePath: remotePath, primaryGroupID: primaryGroupID)
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) throws -> Session {
        try AsyncOperationSupport.blocking { try await self.launchOrResumeDefaultSession(workspaceID: workspaceID, providerID: providerID) }
    }

    func launchOrResumeDefaultSession(workspaceID: UUID, providerID: ProviderID) async throws -> Session {
        guard let workspace = try metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        guard providerAdapter(for: providerID).supportsDefaultSessionLaunch(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        if let existingSession = try metadataStore.defaultSession(workspaceID: workspaceID, providerID: providerID) {
            return try await launchOrResumeSession(existingSession, workspace: workspace)
        }

        let remoteContext = try remoteWorkspaceTargetOverview(for: workspace, refreshHostValidation: true).map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }
        let health = try await providerHealthSummary(
            for: providerID,
            workspace: workspace,
            remoteContext: remoteContext,
            preferFreshRemoteCheck: true
        )
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            let failureMessage = health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
            return try metadataStore.createDefaultSession(
                workspaceID: workspaceID,
                providerID: providerID,
                state: .failed,
                failureMessage: failureMessage
            )
        }

        let session = try metadataStore.createDefaultSession(
            workspaceID: workspaceID,
            providerID: providerID,
            state: .ready,
            failureMessage: nil
        )
        let launchSnapshot = try metadataStore.ensureLaunchSnapshot(
            sessionID: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            primarySurface: providerAdapter(for: session.providerID).primarySurface(in: workspace),
            resolvedExecutable: executable,
            resolvedWorkingDirectory: workspace.folderPath
        )
        return try await launchSession(session, workspace: workspace, launchSnapshot: launchSnapshot, forceFreshRemoteRuntime: true)
    }

    func launchOrResumeSession(sessionID: UUID) throws -> Session {
        try AsyncOperationSupport.blocking { try await self.launchOrResumeSession(sessionID: sessionID) }
    }

    func launchOrResumeSession(sessionID: UUID) async throws -> Session {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }
        guard let workspace = try metadataStore.workspace(id: session.workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        return try await launchOrResumeSession(session, workspace: workspace)
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) throws -> Session {
        try AsyncOperationSupport.blocking { try await self.createNamedSession(workspaceID: workspaceID, providerID: providerID, name: name) }
    }

    func createNamedSession(workspaceID: UUID, providerID: ProviderID, name: String?) async throws -> Session {
        guard let workspace = try metadataStore.workspace(id: workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }

        guard providerAdapter(for: providerID).supportsNamedSessions(in: workspace) else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let existingSessions = try metadataStore.listSessions(workspaceID: workspaceID, providerID: providerID)
        let resolvedName = resolveNamedSessionName(name, existingSessions: existingSessions)
        let remoteContext = try remoteWorkspaceTargetOverview(for: workspace, refreshHostValidation: true).map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }
        let health = try await providerHealthSummary(
            for: providerID,
            workspace: workspace,
            remoteContext: remoteContext,
            preferFreshRemoteCheck: true
        )

        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            let failureMessage = health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
            return try metadataStore.createNamedSession(
                workspaceID: workspaceID,
                providerID: providerID,
                name: resolvedName,
                state: .failed,
                failureMessage: failureMessage
            )
        }

        let session = try metadataStore.createNamedSession(
            workspaceID: workspaceID,
            providerID: providerID,
            name: resolvedName,
            state: .ready,
            failureMessage: nil
        )
        let launchSnapshot = try metadataStore.ensureLaunchSnapshot(
            sessionID: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            primarySurface: providerAdapter(for: session.providerID).primarySurface(in: workspace),
            resolvedExecutable: executable,
            resolvedWorkingDirectory: workspace.folderPath
        )
        return try await launchSession(session, workspace: workspace, launchSnapshot: launchSnapshot, forceFreshRemoteRuntime: true)
    }

    func stopSession(sessionID: UUID) throws -> Session {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            return resolvedSession
        }

        if try stopRequiresActiveIBMBobTurn(resolvedSession), sessionRuntimeManager.hasRuntime(for: resolvedSession) == false {
            throw IBMBobSessionRuntimeError.noActiveTurnToStop
        }

        try sessionRuntimeManager.stop(session: resolvedSession)
        guard let updatedSession = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }
        return try reconcileSessionRuntimeState(updatedSession)
    }

    func deleteSessionRecord(sessionID: UUID) throws -> Bool {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        if resolvedSession.state == .ready,
           try readySessionRecordMayBeDeleted(resolvedSession) == false {
            throw NexusMetadataStoreError.sessionRecordDeletionRequiresStoppedSession
        }

        guard let workspace = try metadataStore.workspace(id: resolvedSession.workspaceID) else {
            throw NexusMetadataStoreError.workspaceNotFound
        }
        let sessionRecordAdapterMetadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: resolvedSession.id)
        ibmBobNativeSessionCleaner.bestEffortDeleteStoredContinuity(
            for: resolvedSession,
            workspace: workspace,
            sessionRecordAdapterMetadata: sessionRecordAdapterMetadata
        )

        sessionRuntimeManager.remove(session: resolvedSession)
        return try metadataStore.deleteSession(id: sessionID)
    }

    func getSessionRecord(sessionID: UUID) throws -> Session {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        return try reconcileSessionRuntimeState(session)
    }

    func getSessionScreen(sessionID: UUID) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)

        switch resolvedSession.state {
        case .failed:
            return try staticSessionScreen(
                for: resolvedSession,
                transcript: resolvedSession.failureMessage ?? "Session launch failed"
            )
        case .interrupted:
            return try staticSessionScreen(
                for: resolvedSession,
                transcript: resolvedSession.failureMessage ?? "Session interrupted"
            )
        case .exited:
            if sessionRuntimeManager.hasRuntime(for: resolvedSession) {
                return normalizedSessionScreen(try sessionRuntimeManager.sessionScreen(for: resolvedSession))
            }
            return try staticSessionScreen(
                for: resolvedSession,
                transcript: resolvedSession.failureMessage ?? "Session exited"
            )
        case .ready:
            if sessionRuntimeManager.hasRuntime(for: resolvedSession) {
                return normalizedSessionScreen(try sessionRuntimeManager.sessionScreen(for: resolvedSession))
            }
            return try staticSessionScreen(for: resolvedSession, transcript: "")
        }
    }

    func observeSessionScreen(
        observationID: UUID,
        sessionID: UUID,
        onUpdate: @escaping @Sendable (SessionScreen) -> Void
    ) throws -> SessionScreenObservationStart {
        let screen = try getSessionScreen(sessionID: sessionID)
        sessionRuntimeManager.addUpdateObserver(id: observationID, for: screen.session) { [weak self] in
            guard let self else {
                return
            }

            do {
                onUpdate(try self.getSessionScreen(sessionID: sessionID))
            } catch {
                return
            }
        }

        return SessionScreenObservationStart(observationID: observationID, screen: screen)
    }

    func cancelSessionScreenObservation(observationID: UUID) {
        sessionRuntimeManager.removeUpdateObserver(id: observationID)
    }

    func sendSessionInput(sessionID: UUID, text: String) throws -> SessionScreen {
        try AsyncOperationSupport.blocking { try await self.sendSessionInput(sessionID: sessionID, text: text) }
    }

    func sendSessionInput(sessionID: UUID, text: String) async throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        _ = try claimMacController(for: resolvedSession)
        return normalizedSessionScreen(try sessionRuntimeManager.sendInput(text, to: resolvedSession))
    }

    func sendSessionText(sessionID: UUID, text: String) throws -> SessionScreen {
        try AsyncOperationSupport.blocking { try await self.sendSessionText(sessionID: sessionID, text: text) }
    }

    func sendSessionText(sessionID: UUID, text: String) async throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        let screenBeforeInput = try claimMacController(for: resolvedSession)
        let responseScreen = normalizedSessionScreen(try sessionRuntimeManager.sendText(text, to: resolvedSession))
        return stabilizedScreenAfterTerminalInput(
            for: resolvedSession,
            screenBeforeInput: screenBeforeInput,
            immediateResponseScreen: responseScreen
        )
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) throws -> SessionScreen {
        try AsyncOperationSupport.blocking { try await self.sendSessionInputKey(sessionID: sessionID, key: key) }
    }

    func sendSessionInputKey(sessionID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        let currentScreen = try claimMacController(for: resolvedSession)
        let renderState = TerminalRenderer.renderState(
            from: currentScreen.transcript,
            terminalColumns: currentScreen.terminalColumns,
            terminalRows: currentScreen.terminalRows
        )

        let responseScreen = normalizedSessionScreen(
            try sessionRuntimeManager.sendInputKey(
                key,
                applicationCursorMode: renderState.applicationCursorMode,
                to: resolvedSession
            )
        )
        return stabilizedScreenAfterTerminalInput(
            for: resolvedSession,
            screenBeforeInput: currentScreen,
            immediateResponseScreen: responseScreen
        )
    }

    func respondToApprovalRequest(
        sessionID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) throws -> SessionScreen {
        try AsyncOperationSupport.blocking {
            try await self.respondToApprovalRequest(
                sessionID: sessionID,
                approvalRequestID: approvalRequestID,
                decision: decision
            )
        }
    }

    func respondToApprovalRequest(
        sessionID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        _ = try claimMacController(for: resolvedSession)
        return normalizedSessionScreen(
            try sessionRuntimeManager.respondToApprovalRequest(
                approvalRequestID,
                decision: decision,
                to: resolvedSession
            )
        )
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) throws -> SessionScreen {
        try AsyncOperationSupport.blocking { try await self.resizeSession(sessionID: sessionID, columns: columns, rows: rows) }
    }

    func resizeSession(sessionID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        _ = sessionControllerRegistry.claimMacControl(sessionID: resolvedSession.id, preferredSize: (columns, rows))
        let screen = try sessionRuntimeManager.resize(session: resolvedSession, columns: columns, rows: rows)
        try metadataStore.updateSessionTerminalSize(
            id: resolvedSession.id,
            columns: screen.terminalColumns,
            rows: screen.terminalRows
        )
        return normalizedSessionScreen(screen)
    }

    func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) throws -> SessionScreen {
        try AsyncOperationSupport.blocking {
            try await self.takeRemoteSessionControl(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                columns: columns,
                rows: rows
            )
        }
    }

    func takeRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID, columns: Int, rows: Int) async throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }

        let currentScreen = try sessionRuntimeManager.sessionScreen(for: resolvedSession)
        sessionControllerRegistry.takeRemoteControl(
            sessionID: resolvedSession.id,
            pairedDeviceID: pairedDeviceID,
            currentMacSize: (currentScreen.terminalColumns, currentScreen.terminalRows)
        )

        let resizedScreen = try sessionRuntimeManager.resize(session: resolvedSession, columns: columns, rows: rows)
        try metadataStore.updateSessionTerminalSize(
            id: resolvedSession.id,
            columns: resizedScreen.terminalColumns,
            rows: resizedScreen.terminalRows
        )
        return normalizedSessionScreen(resizedScreen)
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) throws -> SessionScreen {
        try AsyncOperationSupport.blocking {
            try await self.sendRemoteSessionInput(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: text)
        }
    }

    func sendRemoteSessionInput(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        let resolvedSession = try await readyRemoteControlledSession(
            sessionID: sessionID,
            pairedDeviceID: pairedDeviceID,
            controllerError: .remoteSessionInputControllerRequired
        )
        return normalizedSessionScreen(try sessionRuntimeManager.sendInput(text, to: resolvedSession))
    }

    func respondToRemoteApprovalRequest(
        sessionID: UUID,
        pairedDeviceID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) throws -> SessionScreen {
        try AsyncOperationSupport.blocking {
            try await self.respondToRemoteApprovalRequest(
                sessionID: sessionID,
                pairedDeviceID: pairedDeviceID,
                approvalRequestID: approvalRequestID,
                decision: decision
            )
        }
    }

    func respondToRemoteApprovalRequest(
        sessionID: UUID,
        pairedDeviceID: UUID,
        approvalRequestID: UUID,
        decision: ApprovalRequestDecision
    ) async throws -> SessionScreen {
        let resolvedSession = try await readyRemoteControlledSession(
            sessionID: sessionID,
            pairedDeviceID: pairedDeviceID,
            controllerError: .remoteApprovalRequestControllerRequired
        )
        return normalizedSessionScreen(
            try sessionRuntimeManager.respondToApprovalRequest(
                approvalRequestID,
                decision: decision,
                to: resolvedSession
            )
        )
    }

    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) throws -> SessionScreen {
        try AsyncOperationSupport.blocking {
            try await self.sendRemoteSessionText(sessionID: sessionID, pairedDeviceID: pairedDeviceID, text: text)
        }
    }

    func sendRemoteSessionText(sessionID: UUID, pairedDeviceID: UUID, text: String) async throws -> SessionScreen {
        let resolvedSession = try await readyRemoteControlledSession(sessionID: sessionID, pairedDeviceID: pairedDeviceID)
        let screenBeforeInput = normalizedSessionScreen(try sessionRuntimeManager.sessionScreen(for: resolvedSession))
        let responseScreen = normalizedSessionScreen(try sessionRuntimeManager.sendText(text, to: resolvedSession))
        return stabilizedScreenAfterTerminalInput(
            for: resolvedSession,
            screenBeforeInput: screenBeforeInput,
            immediateResponseScreen: responseScreen
        )
    }

    func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) throws -> SessionScreen {
        try AsyncOperationSupport.blocking {
            try await self.sendRemoteSessionInputKey(sessionID: sessionID, pairedDeviceID: pairedDeviceID, key: key)
        }
    }

    func sendRemoteSessionInputKey(sessionID: UUID, pairedDeviceID: UUID, key: SessionInputKey) async throws -> SessionScreen {
        let resolvedSession = try await readyRemoteControlledSession(sessionID: sessionID, pairedDeviceID: pairedDeviceID)
        let currentScreen = normalizedSessionScreen(try sessionRuntimeManager.sessionScreen(for: resolvedSession))
        let renderState = TerminalRenderer.renderState(
            from: currentScreen.transcript,
            terminalColumns: currentScreen.terminalColumns,
            terminalRows: currentScreen.terminalRows
        )

        let responseScreen = normalizedSessionScreen(
            try sessionRuntimeManager.sendInputKey(
                key,
                applicationCursorMode: renderState.applicationCursorMode,
                to: resolvedSession
            )
        )
        return stabilizedScreenAfterTerminalInput(
            for: resolvedSession,
            screenBeforeInput: currentScreen,
            immediateResponseScreen: responseScreen
        )
    }

    func releaseRemoteSessionControl(sessionID: UUID, pairedDeviceID: UUID) throws -> SessionScreen {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }
        guard let macSize = sessionControllerRegistry.releaseRemoteControl(sessionID: resolvedSession.id, pairedDeviceID: pairedDeviceID) else {
            throw NexusSessionControlError.remoteControllerRequired
        }

        let resizedScreen = try sessionRuntimeManager.resize(session: resolvedSession, columns: macSize.columns, rows: macSize.rows)
        try metadataStore.updateSessionTerminalSize(
            id: resolvedSession.id,
            columns: resizedScreen.terminalColumns,
            rows: resizedScreen.terminalRows
        )
        return normalizedSessionScreen(resizedScreen)
    }

    private func claimMacController(for session: Session) throws -> SessionScreen {
        let currentScreen = try sessionRuntimeManager.sessionScreen(for: session)
        guard let macSize = sessionControllerRegistry.claimMacControl(sessionID: session.id),
              currentScreen.terminalColumns != macSize.columns || currentScreen.terminalRows != macSize.rows else {
            return currentScreen
        }

        let resizedScreen = try sessionRuntimeManager.resize(session: session, columns: macSize.columns, rows: macSize.rows)
        try metadataStore.updateSessionTerminalSize(
            id: session.id,
            columns: resizedScreen.terminalColumns,
            rows: resizedScreen.terminalRows
        )
        return resizedScreen
    }

    private func stabilizedScreenAfterTerminalInput(
        for session: Session,
        screenBeforeInput: SessionScreen,
        immediateResponseScreen: SessionScreen,
        timeoutMicroseconds: useconds_t = 300_000,
        pollIntervalMicroseconds: useconds_t = 20_000
    ) -> SessionScreen {
        guard immediateResponseScreen == screenBeforeInput else {
            return immediateResponseScreen
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + (UInt64(timeoutMicroseconds) * 1_000)
        var latestScreen = immediateResponseScreen

        while DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(pollIntervalMicroseconds)

            guard let refreshedScreen = try? normalizedSessionScreen(sessionRuntimeManager.sessionScreen(for: session)) else {
                break
            }

            latestScreen = refreshedScreen
            if refreshedScreen != screenBeforeInput {
                return refreshedScreen
            }
        }

        return latestScreen
    }

    private func readyRemoteControlledSession(
        sessionID: UUID,
        pairedDeviceID: UUID,
        controllerError: NexusSessionControlError = .remoteControllerRequired
    ) async throws -> Session {
        guard let session = try metadataStore.session(id: sessionID) else {
            throw NexusMetadataStoreError.sessionNotFound
        }

        let resolvedSession = try await interactiveReadySession(for: session)
        guard resolvedSession.state == .ready else {
            throw NexusMetadataStoreError.sessionNotReady
        }
        guard sessionControllerRegistry.isRemoteController(sessionID: resolvedSession.id, pairedDeviceID: pairedDeviceID) else {
            throw controllerError
        }
        return resolvedSession
    }

    private func interactiveReadySession(for session: Session) async throws -> Session {
        let resolvedSession = try reconcileSessionRuntimeState(session)
        guard resolvedSession.state == .ready else {
            return resolvedSession
        }

        guard sessionRuntimeManager.hasRuntime(for: resolvedSession) == false else {
            return resolvedSession
        }

        guard let workspace = try metadataStore.workspace(id: resolvedSession.workspaceID),
              try sessionMayRemainReadyWithoutRuntime(resolvedSession, workspace: workspace) else {
            return resolvedSession
        }

        _ = try await launchOrResumeSession(resolvedSession, workspace: workspace)
        return resolvedSession
    }

    private func launchOrResumeSession(_ existingSession: Session, workspace: Workspace) async throws -> Session {
        let adapter = providerAdapter(for: existingSession.providerID)
        let isSupported = existingSession.isDefault
            ? adapter.supportsDefaultSessionLaunch(in: workspace)
            : adapter.supportsNamedSessions(in: workspace)
        guard isSupported else {
            throw NexusMetadataStoreError.providerNotSupported
        }

        let reconciledSession = try reconcileSessionRuntimeState(existingSession)
        let sessionRecordAdapterMetadataSource = try relaunchSessionRecordAdapterMetadataSource(for: reconciledSession)

        if let launchSnapshot = try metadataStore.launchSnapshot(sessionID: reconciledSession.id) {
            if shouldAttemptRemoteRuntimeRecovery(for: reconciledSession, workspace: workspace) {
                return try await recoverRemoteSession(
                    reconciledSession,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot
                )
            }

            let session = reconciledSession.state == .ready && reconciledSession.failureMessage == nil
                ? reconciledSession
                : try metadataStore.updateSession(id: reconciledSession.id, state: .ready, failureMessage: nil)
            return try await launchSession(
                session,
                workspace: workspace,
                launchSnapshot: launchSnapshot,
                forceFreshRemoteRuntime: shouldCreateFreshRemoteRuntime(for: reconciledSession, workspace: workspace),
                sessionRecordAdapterMetadataSource: sessionRecordAdapterMetadataSource
            )
        }

        let remoteContext = try remoteWorkspaceTargetOverview(for: workspace, refreshHostValidation: true).map {
            RemoteWorkspaceHealthContext(
                host: $0.host,
                hostValidation: $0.hostValidation,
                workspaceAvailability: $0.workspaceAvailability
            )
        }
        let health = try await providerHealthSummary(
            for: reconciledSession.providerID,
            workspace: workspace,
            remoteContext: remoteContext,
            preferFreshRemoteCheck: true
        )
        guard health.launchability == .launchable, let executable = health.resolvedExecutable else {
            let failureMessage = health.diagnostics.first(where: { $0.severity == .error })?.message ?? health.summary
            return try metadataStore.updateSession(
                id: reconciledSession.id,
                state: .failed,
                failureMessage: failureMessage
            )
        }

        let session = reconciledSession.state == .ready && reconciledSession.failureMessage == nil
            ? reconciledSession
            : try metadataStore.updateSession(id: reconciledSession.id, state: .ready, failureMessage: nil)
        let launchSnapshot = try metadataStore.ensureLaunchSnapshot(
            sessionID: session.id,
            workspaceID: session.workspaceID,
            providerID: session.providerID,
            primarySurface: providerAdapter(for: session.providerID).primarySurface(in: workspace),
            resolvedExecutable: executable,
            resolvedWorkingDirectory: workspace.folderPath
        )
        return try await launchSession(
            session,
            workspace: workspace,
            launchSnapshot: launchSnapshot,
            forceFreshRemoteRuntime: shouldCreateFreshRemoteRuntime(for: reconciledSession, workspace: workspace),
            sessionRecordAdapterMetadataSource: sessionRecordAdapterMetadataSource
        )
    }

    private func relaunchSessionRecordAdapterMetadataSource(for session: Session) throws -> SessionRecordAdapterMetadataLaunchSource {
        guard session.providerID == .ibmBob,
              session.state != .ready else {
            return .stored
        }

        let storedMetadata = try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)
        if session.state == .interrupted,
           let linkage = storedMetadata?.ibmBobSessionLinkage {
            return .explicit(
                SessionRecordAdapterMetadata.ibmBob(
                    sessionID: linkage.sessionID,
                    activityItems: linkage.persistedActivityItems,
                    turnInProgress: false
                )
            )
        }

        let storedSessionID = storedMetadata?.ibmBobSessionLinkage?.sessionID
        return .explicit(SessionRecordAdapterMetadata.ibmBob(sessionID: storedSessionID))
    }

    private func shouldAttemptRemoteRuntimeRecovery(for session: Session, workspace: Workspace) -> Bool {
        guard workspace.kind == .remote else {
            return false
        }

        if (try? sessionMayRemainReadyWithoutRuntime(session, workspace: workspace)) == true {
            return false
        }

        let runtimeState = sessionRuntimeManager.runtimeState(for: session)
        if sessionRuntimeManager.hasRuntime(for: session), runtimeState != .interrupted {
            return false
        }

        switch session.state {
        case .ready, .interrupted:
            return true
        case .exited, .failed:
            return false
        }
    }

    private func shouldCreateFreshRemoteRuntime(for session: Session, workspace: Workspace) -> Bool {
        guard workspace.kind == .remote else {
            return false
        }

        guard shouldAttemptRemoteRuntimeRecovery(for: session, workspace: workspace) == false else {
            return false
        }

        return sessionRuntimeManager.runtimeState(for: session) != .ready
    }

    private func remoteRuntimeIdentifier(for session: Session, forceNew: Bool) throws -> String {
        let currentGeneration = try metadataStore.remoteRuntimeGeneration(sessionID: session.id)
        if forceNew {
            let nextGeneration = try metadataStore.advanceRemoteRuntimeGeneration(sessionID: session.id)
            return remoteRuntimeIdentifier(sessionID: session.id, generation: nextGeneration)
        }

        if currentGeneration == 0 {
            return legacyRemoteRuntimeIdentifier(for: session)
        }

        return remoteRuntimeIdentifier(sessionID: session.id, generation: currentGeneration)
    }

    private func legacyRemoteRuntimeIdentifier(for session: Session) -> String {
        "nexus-\(session.id.uuidString.lowercased())"
    }

    private func remoteRuntimeIdentifier(sessionID: UUID, generation: Int) -> String {
        "nexus-\(sessionID.uuidString.lowercased())-runtime-\(generation)"
    }

    private func recoverRemoteSession(
        _ session: Session,
        workspace: Workspace,
        launchSnapshot: LaunchSnapshot
    ) async throws -> Session {
        let readySession = session.state == .ready && session.failureMessage == nil
            ? session
            : try metadataStore.updateSession(id: session.id, state: .ready, failureMessage: nil)

        do {
            try await sessionRuntimeManager.launchOrResume(
                session: readySession,
                workspace: workspace,
                launchConfiguration: try runtimeLaunchConfiguration(
                    for: readySession,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot,
                    forceFreshRemoteRuntime: false,
                    remoteRuntimeLaunchMode: .attachExisting
                )
            )
            try persistRuntimeLinkageIfNeeded(for: readySession)
            let terminalSize = try metadataStore.sessionTerminalSize(id: readySession.id)
            let screen = try sessionRuntimeManager.resize(
                session: readySession,
                columns: terminalSize.columns,
                rows: terminalSize.rows
            )
            try persistPrimarySurfaceIfNeeded(for: readySession, primarySurface: screen.primarySurface)
            return readySession
        } catch {
            let failureContext = try remoteRuntimeRecoveryFailureContext(for: error, session: readySession, workspace: workspace)
            if failureContext.isMissingRemoteRuntime {
                return try await launchSession(
                    readySession,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot,
                    forceFreshRemoteRuntime: true
                )
            }

            let failure = providerAdapter(for: readySession.providerID).remoteRuntimeRecoveryFailure(for: failureContext)
            return try metadataStore.updateSession(
                id: readySession.id,
                state: failure.state,
                failureMessage: failure.message
            )
        }
    }

    private func launchSession(
        _ session: Session,
        workspace: Workspace,
        launchSnapshot: LaunchSnapshot,
        forceFreshRemoteRuntime: Bool = false,
        sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource = .stored
    ) async throws -> Session {
        do {
            try await sessionRuntimeManager.launchOrResume(
                session: session,
                workspace: workspace,
                launchConfiguration: try runtimeLaunchConfiguration(
                    for: session,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot,
                    forceFreshRemoteRuntime: forceFreshRemoteRuntime,
                    sessionRecordAdapterMetadataSource: sessionRecordAdapterMetadataSource,
                    remoteRuntimeLaunchMode: .launchNew
                )
            )
            try persistRuntimeLinkageIfNeeded(for: session)
            let terminalSize = try metadataStore.sessionTerminalSize(id: session.id)
            let screen = try sessionRuntimeManager.resize(
                session: session,
                columns: terminalSize.columns,
                rows: terminalSize.rows
            )
            try persistPrimarySurfaceIfNeeded(for: session, primarySurface: screen.primarySurface)
            return session
        } catch {
            if try shouldRetryFreshPiLaunchWithoutPersistedLinkage(
                for: session,
                workspace: workspace,
                forceFreshRemoteRuntime: forceFreshRemoteRuntime,
                sessionRecordAdapterMetadataSource: sessionRecordAdapterMetadataSource,
                error: error
            ) {
                return try await launchSession(
                    session,
                    workspace: workspace,
                    launchSnapshot: launchSnapshot,
                    forceFreshRemoteRuntime: true,
                    sessionRecordAdapterMetadataSource: .explicit(nil)
                )
            }

            return try metadataStore.updateSession(
                id: session.id,
                state: .failed,
                failureMessage: error.localizedDescription
            )
        }
    }

    private func shouldRetryFreshPiLaunchWithoutPersistedLinkage(
        for session: Session,
        workspace: Workspace,
        forceFreshRemoteRuntime: Bool,
        sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource,
        error: Error
    ) throws -> Bool {
        guard session.providerID == .pi,
              workspace.kind == .remote,
              forceFreshRemoteRuntime else {
            return false
        }

        guard let metadata = try resolvedSessionRecordAdapterMetadata(
            for: session,
            source: sessionRecordAdapterMetadataSource
        ), metadata.piSessionLinkage != nil else {
            return false
        }

        let normalized = error.localizedDescription.lowercased()
        return normalized.contains("invalid pi session")
            || normalized.contains("invalid session")
            || normalized.contains("session not found")
    }

    private func resolvedSessionRecordAdapterMetadata(
        for session: Session,
        source: SessionRecordAdapterMetadataLaunchSource
    ) throws -> SessionRecordAdapterMetadata? {
        switch source {
        case .stored:
            try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)
        case let .explicit(metadata):
            metadata
        }
    }

    private func persistRuntimeLinkageIfNeeded(for session: Session) throws {
        guard let metadata = sessionRuntimeManager.sessionRecordAdapterMetadata(for: session),
              metadata.isEmpty == false else {
            return
        }

        try metadataStore.saveSessionRecordAdapterMetadata(sessionID: session.id, metadata: metadata)
    }

    private func persistRuntimeLinkageAfterRuntimeChange(sessionID: UUID) {
        guard let session = (try? metadataStore.session(id: sessionID)) ?? nil else {
            return
        }

        try? persistRuntimeLinkageIfNeeded(for: session)
    }

    private func persistSessionStateAfterRuntimeChange(sessionID: UUID) {
        guard let session = (try? metadataStore.session(id: sessionID)) ?? nil,
              let runtimeState = sessionRuntimeManager.runtimeState(for: session),
              runtimeState != .ready else {
            return
        }

        _ = try? updatedSessionForRuntimeState(session, runtimeState: runtimeState)
    }

    private func updatedSessionForRuntimeState(_ session: Session, runtimeState: Session.State) throws -> Session {
        switch runtimeState {
        case .ready:
            return session
        case .failed:
            return try metadataStore.updateSession(
                id: session.id,
                state: .failed,
                failureMessage: runtimeFailureMessage(for: session) ?? "Session failed"
            )
        case .interrupted:
            let runtimeTranscript = try? sessionRuntimeManager.sessionScreen(for: session).transcript
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackFailureMessage = try interruptedSessionFailureMessage(
                for: session,
                workspace: metadataStore.workspace(id: session.workspaceID)
            )
            let failureMessage = runtimeTranscript.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackFailureMessage
            return try metadataStore.updateSession(
                id: session.id,
                state: .interrupted,
                failureMessage: failureMessage
            )
        case .exited:
            return try metadataStore.updateSession(
                id: session.id,
                state: .exited,
                failureMessage: "Session exited. Relaunch to start a new live runtime."
            )
        }
    }

    private func runtimeFailureMessage(for session: Session) -> String? {
        guard let screen = try? sessionRuntimeManager.sessionScreen(for: session) else {
            return nil
        }

        if let errorText = screen.activityItems.last(where: { $0.kind == .error })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
           errorText.isEmpty == false {
            return errorText
        }

        let transcript = screen.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private func persistPrimarySurfaceIfNeeded(for session: Session, primarySurface: SessionSurface) throws {
        guard let launchSnapshot = try metadataStore.launchSnapshot(sessionID: session.id),
              launchSnapshot.primarySurface != primarySurface else {
            return
        }

        try metadataStore.updateLaunchSnapshotPrimarySurface(sessionID: session.id, primarySurface: primarySurface)
    }

    private func remoteRuntimeRecoveryFailure(
        for error: Error,
        session: Session,
        workspace: Workspace
    ) throws -> (state: Session.State, message: String) {
        providerAdapter(for: session.providerID).remoteRuntimeRecoveryFailure(
            for: try remoteRuntimeRecoveryFailureContext(for: error, session: session, workspace: workspace)
        )
    }

    private func remoteRuntimeRecoveryFailureContext(
        for error: Error,
        session: Session,
        workspace: Workspace
    ) throws -> RemoteRuntimeRecoveryFailureContext {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let runtimeIdentifier = try remoteRuntimeIdentifier(for: session, forceNew: false)
        let hostName = try workspace.remoteHostID.flatMap { try metadataStore.host(id: $0)?.name } ?? workspace.name
        return RemoteRuntimeRecoveryFailureContext(
            detail: detail,
            normalizedDetail: detail.lowercased(),
            runtimeIdentifier: runtimeIdentifier,
            hostName: hostName
        )
    }

    private func runtimeLaunchConfiguration(
        for session: Session,
        workspace: Workspace,
        launchSnapshot: LaunchSnapshot,
        forceFreshRemoteRuntime: Bool,
        sessionRecordAdapterMetadataSource: SessionRecordAdapterMetadataLaunchSource = .stored,
        remoteRuntimeLaunchMode: RemoteRuntimeLaunchMode
    ) throws -> SessionRuntimeLaunchConfiguration {
        let adapter = providerAdapter(for: session.providerID)
        let remoteHost: NexusDomain.Host?
        let resolvedRemoteRuntimeIdentifier: String?
        if workspace.kind == .remote {
            guard let hostID = workspace.remoteHostID,
                  let host = try metadataStore.host(id: hostID) else {
                throw NexusMetadataStoreError.hostNotFound
            }
            remoteHost = host
            resolvedRemoteRuntimeIdentifier = try remoteRuntimeIdentifier(for: session, forceNew: forceFreshRemoteRuntime)
        } else {
            remoteHost = nil
            resolvedRemoteRuntimeIdentifier = nil
        }

        return SessionRuntimeLaunchConfiguration(
            executable: launchSnapshot.resolvedExecutable,
            workingDirectory: launchSnapshot.resolvedWorkingDirectory,
            remoteHost: remoteHost,
            remoteRuntimeIdentifier: resolvedRemoteRuntimeIdentifier,
            remoteRuntimeLaunchMode: remoteRuntimeLaunchMode,
            sessionRecordAdapterMetadata: try resolvedSessionRecordAdapterMetadata(
                for: session,
                source: sessionRecordAdapterMetadataSource
            ),
            initialTranscript: adapter.initialTranscript(
                for: workspace,
                remoteHost: remoteHost,
                launchMode: remoteRuntimeLaunchMode
            ),
            terminationStatusMessageBuilder: { status in
                adapter.terminationStatusMessage(for: status)
            }
        )
    }

    private func staticSessionScreen(for session: Session, transcript: String) throws -> SessionScreen {
        let terminalSize = try metadataStore.sessionTerminalSize(id: session.id)
        let primarySurface = try persistedPrimarySurface(for: session)
        let persistedActivityItems = try persistedStructuredActivityItems(for: session)
        return normalizedSessionScreen(
            SessionScreen(
                session: session,
                primarySurface: primarySurface,
                transcript: staticSessionTranscript(
                    fallbackTranscript: transcript,
                    primarySurface: primarySurface,
                    persistedActivityItems: persistedActivityItems
                ),
                terminalColumns: terminalSize.columns,
                terminalRows: terminalSize.rows,
                activityItems: staticSessionActivityItems(
                    for: session,
                    transcript: transcript,
                    primarySurface: primarySurface,
                    persistedActivityItems: persistedActivityItems
                )
            )
        )
    }

    private func persistedPrimarySurface(for session: Session, workspace: Workspace? = nil) throws -> SessionSurface {
        if let launchSnapshot = try metadataStore.launchSnapshot(sessionID: session.id) {
            return launchSnapshot.primarySurface
        }

        let resolvedWorkspace = if let workspace {
            workspace
        } else {
            try metadataStore.workspace(id: session.workspaceID)
        }
        guard let resolvedWorkspace else {
            return .terminal
        }

        return providerAdapter(for: session.providerID).primarySurface(in: resolvedWorkspace)
    }

    private func persistedStructuredActivityItems(for session: Session) throws -> [SessionActivityItem]? {
        try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)?.ibmBobPersistedActivityItems
    }

    private func staticSessionTranscript(
        fallbackTranscript: String,
        primarySurface: SessionSurface,
        persistedActivityItems: [SessionActivityItem]?
    ) -> String {
        guard primarySurface == .structuredActivityFeed,
              let persistedActivityItems,
              persistedActivityItems.isEmpty == false else {
            return fallbackTranscript
        }

        let transcriptLines = persistedActivityItems.compactMap { item -> String? in
            guard item.kind == .message else {
                return nil
            }
            if item.text.hasPrefix("You: ") {
                return "> \(item.text.dropFirst(5))"
            }
            return item.text
        }

        return transcriptLines.isEmpty ? fallbackTranscript : transcriptLines.joined(separator: "\n")
    }

    private func staticSessionActivityItems(
        for session: Session,
        transcript: String,
        primarySurface: SessionSurface,
        persistedActivityItems: [SessionActivityItem]?
    ) -> [SessionActivityItem] {
        guard primarySurface == .structuredActivityFeed else {
            return []
        }

        if let persistedActivityItems, persistedActivityItems.isEmpty == false {
            return persistedActivityItems
        }

        guard transcript.isEmpty == false else {
            return []
        }

        switch session.state {
        case .failed, .interrupted:
            return [SessionActivityItem(kind: .error, text: transcript)]
        case .ready, .exited:
            return []
        }
    }

    private func navigationItem(_ target: NavigationTarget) throws -> NavigationItem? {
        switch target.kind {
        case .workspace:
            guard let workspaceID = target.workspaceID,
                  let workspace = try metadataStore.workspace(id: workspaceID) else {
                return nil
            }

            return NavigationItem(
                target: .workspace(workspace.id),
                title: workspace.name,
                subtitle: try workspaceNavigationSubtitle(workspace)
            )
        case .provider:
            guard let workspaceID = target.workspaceID,
                  let providerID = target.providerID,
                  let workspace = try metadataStore.workspace(id: workspaceID) else {
                return nil
            }

            return NavigationItem(
                target: .provider(workspaceID: workspace.id, providerID: providerID),
                title: providerID.displayName,
                subtitle: try providerNavigationSubtitle(workspace: workspace)
            )
        case .session:
            guard let sessionID = target.sessionID,
                  let session = try metadataStore.session(id: sessionID),
                  let workspace = try metadataStore.workspace(id: session.workspaceID) else {
                return nil
            }

            return NavigationItem(
                target: .session(session.id),
                title: sessionNavigationTitle(session),
                subtitle: try sessionNavigationSubtitle(session: session, workspace: workspace)
            )
        }
    }

    private func sessionNavigationTitle(_ session: Session) -> String {
        if session.isDefault {
            return "Default Session"
        }

        return session.name ?? "Session"
    }

    private func workspaceNavigationSubtitle(_ workspace: Workspace) throws -> String {
        guard workspace.kind == .remote,
              let hostID = workspace.remoteHostID,
              let host = try metadataStore.host(id: hostID) else {
            return workspace.folderPath
        }

        return "\(host.name) • \(workspace.folderPath)"
    }

    private func providerNavigationSubtitle(workspace: Workspace) throws -> String {
        guard workspace.kind == .remote else {
            return workspace.name
        }

        return "\(workspace.name) • \(try workspaceNavigationSubtitle(workspace))"
    }

    private func sessionNavigationSubtitle(session: Session, workspace: Workspace) throws -> String {
        let base = "\(workspace.name) • \(session.providerID.displayName)"
        guard workspace.kind == .remote else {
            return base
        }

        return "\(base) • \(try workspaceNavigationSubtitle(workspace))"
    }

    private func workspaceSearchFields(_ workspace: Workspace) throws -> [String] {
        var fields = [workspace.name.lowercased(), workspace.folderPath.lowercased()]
        if workspace.kind == .remote,
           let hostID = workspace.remoteHostID,
           let host = try metadataStore.host(id: hostID) {
            fields.append(host.name.lowercased())
            fields.append(host.sshTarget.lowercased())
        }
        return fields
    }

    private func itemMatchesAllTokens(_ tokens: [String], fields: [String]) -> Bool {
        tokens.allSatisfy { token in
            fields.contains { $0.contains(token) }
        }
    }

    private func providerMatchesQuery(tokens: [String], normalizedQuery: String, providerID: ProviderID, workspace: Workspace) throws -> Bool {
        let providerName = providerID.displayName.lowercased()
        if tokens.count == 1 {
            return providerName.contains(normalizedQuery)
        }

        return try itemMatchesAllTokens(tokens, fields: [providerName] + workspaceSearchFields(workspace))
    }

    private func sessionMatchesQuery(tokens: [String], normalizedQuery: String, session: Session, workspace: Workspace) throws -> Bool {
        let sessionName = sessionNavigationTitle(session).lowercased()
        let providerName = session.providerID.displayName.lowercased()
        if tokens.count == 1 {
            return sessionName.contains(normalizedQuery) || providerName.contains(normalizedQuery)
        }

        return try itemMatchesAllTokens(tokens, fields: [sessionName, providerName] + workspaceSearchFields(workspace))
    }

    private func navigationItemSort(_ lhs: NavigationItem, _ rhs: NavigationItem) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func normalizedSessionScreen(_ screen: SessionScreen) -> SessionScreen {
        let renderState = TerminalRenderer.renderState(
            from: screen.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows
        )

        return SessionScreen(
            session: screen.session,
            primarySurface: screen.primarySurface,
            controller: sessionControllerRegistry.controller(for: screen.session.id),
            transcript: renderState.transcript,
            terminalColumns: screen.terminalColumns,
            terminalRows: screen.terminalRows,
            activityItems: screen.activityItems,
            approvalRequests: screen.approvalRequests,
            visibleLines: renderState.visibleLines,
            styledVisibleLines: renderState.styledVisibleLines,
            cursorRow: renderState.cursorRow,
            cursorColumn: renderState.cursorColumn,
            cursorVisible: renderState.cursorVisible
        )
    }

    fileprivate static func renderTerminalState(
        from transcript: String,
        terminalColumns: Int,
        terminalRows: Int
    ) -> (transcript: String, visibleLines: [String], cursorRow: Int, cursorColumn: Int, cursorVisible: Bool, applicationCursorMode: Bool) {
        var lines: [[Character]] = [[]]
        var cursorLine = 0
        var cursorColumn = 0
        var cursorVisible = true
        var applicationCursorMode = false
        var originMode = false
        var savedCursorLine = 0
        var savedCursorColumn = 0
        enum TerminalCharacterSet {
            case ascii
            case lineDrawing
        }

        var usingAlternateBuffer = false
        var scrollRegionTop = 0
        var scrollRegionBottom = max(0, terminalRows - 1)
        var hasExplicitScrollRegion = false
        var g0CharacterSet: TerminalCharacterSet = .ascii
        var g1CharacterSet: TerminalCharacterSet = .ascii
        var usingG1CharacterSet = false
        var lastRenderedCharacter: Character?
        var primaryBufferLines = lines
        var primaryBufferCursorLine = cursorLine
        var primaryBufferCursorColumn = cursorColumn
        var primaryBufferCursorVisible = cursorVisible
        var primaryBufferApplicationCursorMode = applicationCursorMode
        var primaryBufferOriginMode = originMode
        var primaryBufferSavedCursorLine = savedCursorLine
        var primaryBufferSavedCursorColumn = savedCursorColumn
        var primaryBufferScrollRegionTop = scrollRegionTop
        var primaryBufferScrollRegionBottom = scrollRegionBottom
        var primaryBufferHasExplicitScrollRegion = hasExplicitScrollRegion
        var primaryBufferG0CharacterSet = g0CharacterSet
        var primaryBufferG1CharacterSet = g1CharacterSet
        var primaryBufferUsingG1CharacterSet = usingG1CharacterSet
        var iterator = transcript.unicodeScalars.makeIterator()

        func ensureLine(_ lineIndex: Int) {
            while lines.count <= lineIndex {
                lines.append([])
            }
        }

        func ensureCurrentLine() {
            ensureLine(cursorLine)
        }

        func activeScrollRegion() -> ClosedRange<Int>? {
            guard hasExplicitScrollRegion else {
                return nil
            }

            let top = max(0, scrollRegionTop)
            let bottom = max(top, scrollRegionBottom)
            ensureLine(bottom)
            return top...bottom
        }

        func explicitScrollRegion() -> ClosedRange<Int> {
            let top = max(0, scrollRegionTop)
            let bottom = max(top, scrollRegionBottom)
            ensureLine(bottom)
            return top...bottom
        }

        func scrollUpWithinRegion(_ count: Int) {
            let region = explicitScrollRegion()
            let scrollCount = max(0, count)
            guard scrollCount > 0 else {
                return
            }

            let regionHeight = region.count
            if scrollCount >= regionHeight {
                for lineIndex in region {
                    lines[lineIndex] = []
                }
                return
            }

            lines.removeSubrange(region.lowerBound..<(region.lowerBound + scrollCount))
            lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: region.upperBound - scrollCount + 1)
        }

        func scrollDownWithinRegion(_ count: Int) {
            let region = explicitScrollRegion()
            let scrollCount = max(0, count)
            guard scrollCount > 0 else {
                return
            }

            let regionHeight = region.count
            if scrollCount >= regionHeight {
                for lineIndex in region {
                    lines[lineIndex] = []
                }
                return
            }

            lines.removeSubrange((region.upperBound - scrollCount + 1)...region.upperBound)
            lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: region.lowerBound)
        }

        func insertBlankLinesWithinRegion(_ count: Int, at lineIndex: Int) {
            let region = explicitScrollRegion()
            guard region.contains(lineIndex) else {
                return
            }

            let insertCount = min(max(0, count), region.upperBound - lineIndex + 1)
            guard insertCount > 0 else {
                return
            }

            let regionSlice = Array(lines[lineIndex...region.upperBound])
            let replacement = Array(repeating: [Character](), count: insertCount) + Array(regionSlice.dropLast(insertCount))
            lines.replaceSubrange(lineIndex...region.upperBound, with: replacement)
        }

        func deleteLinesWithinRegion(_ count: Int, at lineIndex: Int) {
            let region = explicitScrollRegion()
            guard region.contains(lineIndex) else {
                return
            }

            let deleteCount = min(max(0, count), region.upperBound - lineIndex + 1)
            guard deleteCount > 0 else {
                return
            }

            let regionSlice = Array(lines[lineIndex...region.upperBound])
            let replacement = Array(regionSlice.dropFirst(deleteCount)) + Array(repeating: [Character](), count: deleteCount)
            lines.replaceSubrange(lineIndex...region.upperBound, with: replacement)
        }

        func csiParameters(_ parameters: String) -> [Int?] {
            guard parameters.isEmpty == false else {
                return []
            }

            return parameters
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { segment in
                    guard segment.isEmpty == false else {
                        return nil
                    }
                    return Int(segment)
                }
        }

        func skipStringCommand(allowBellTerminator: Bool) {
            while let scalar = iterator.next() {
                if allowBellTerminator, scalar == "\u{0007}" {
                    return
                }

                if scalar == "\u{001B}", let terminator = iterator.next(), terminator == "\\" {
                    return
                }
            }
        }

        func skipOperatingSystemCommand() {
            skipStringCommand(allowBellTerminator: true)
        }

        func characterSet(for designator: UnicodeScalar) -> TerminalCharacterSet? {
            switch designator {
            case "0":
                .lineDrawing
            case "B":
                .ascii
            default:
                nil
            }
        }

        func renderedCharacter(for scalar: UnicodeScalar) -> Character {
            let activeCharacterSet = usingG1CharacterSet ? g1CharacterSet : g0CharacterSet
            guard activeCharacterSet == .lineDrawing else {
                return Character(scalar)
            }

            switch scalar {
            case "j": return "┘"
            case "k": return "┐"
            case "l": return "┌"
            case "m": return "└"
            case "n": return "┼"
            case "q": return "─"
            case "t": return "├"
            case "u": return "┤"
            case "v": return "┴"
            case "w": return "┬"
            case "x": return "│"
            default: return Character(scalar)
            }
        }

        func parseCSI(finalCharacter: UnicodeScalar, parameters: String) {
            let finalCharacter = Character(finalCharacter)
            let isPrivateMode = parameters.first == "?"
            let normalizedParameters = isPrivateMode ? String(parameters.dropFirst()) : parameters
            let values = csiParameters(normalizedParameters)
            let value = values.first.flatMap { $0 }
            let defaultValue = value ?? 1
            let eraseMode = value ?? 0

            if isPrivateMode {
                switch finalCharacter {
                case "h":
                    switch value {
                    case 1:
                        applicationCursorMode = true
                    case 6:
                        originMode = true
                    case 47, 1047, 1049:
                        guard usingAlternateBuffer == false else {
                            break
                        }
                        primaryBufferLines = lines
                        primaryBufferCursorLine = cursorLine
                        primaryBufferCursorColumn = cursorColumn
                        primaryBufferCursorVisible = cursorVisible
                        primaryBufferApplicationCursorMode = applicationCursorMode
                        primaryBufferOriginMode = originMode
                        primaryBufferSavedCursorLine = savedCursorLine
                        primaryBufferSavedCursorColumn = savedCursorColumn
                        primaryBufferScrollRegionTop = scrollRegionTop
                        primaryBufferScrollRegionBottom = scrollRegionBottom
                        primaryBufferHasExplicitScrollRegion = hasExplicitScrollRegion
                        primaryBufferG0CharacterSet = g0CharacterSet
                        primaryBufferG1CharacterSet = g1CharacterSet
                        primaryBufferUsingG1CharacterSet = usingG1CharacterSet
                        lines = [[]]
                        cursorLine = 0
                        cursorColumn = 0
                        usingAlternateBuffer = true
                    case 25:
                        cursorVisible = true
                    case 1048:
                        savedCursorLine = cursorLine
                        savedCursorColumn = cursorColumn
                    default:
                        break
                    }
                case "l":
                    switch value {
                    case 1:
                        applicationCursorMode = false
                    case 6:
                        originMode = false
                    case 25:
                        cursorVisible = false
                    case 47, 1047, 1049:
                        guard usingAlternateBuffer else {
                            break
                        }
                        lines = primaryBufferLines
                        cursorLine = primaryBufferCursorLine
                        cursorColumn = primaryBufferCursorColumn
                        cursorVisible = primaryBufferCursorVisible
                        applicationCursorMode = primaryBufferApplicationCursorMode
                        originMode = primaryBufferOriginMode
                        savedCursorLine = primaryBufferSavedCursorLine
                        savedCursorColumn = primaryBufferSavedCursorColumn
                        scrollRegionTop = primaryBufferScrollRegionTop
                        scrollRegionBottom = primaryBufferScrollRegionBottom
                        hasExplicitScrollRegion = primaryBufferHasExplicitScrollRegion
                        g0CharacterSet = primaryBufferG0CharacterSet
                        g1CharacterSet = primaryBufferG1CharacterSet
                        usingG1CharacterSet = primaryBufferUsingG1CharacterSet
                        usingAlternateBuffer = false
                    case 1048:
                        cursorLine = savedCursorLine
                        cursorColumn = savedCursorColumn
                        ensureCurrentLine()
                    default:
                        break
                    }
                default:
                    break
                }
                return
            }

            switch finalCharacter {
            case "A":
                cursorLine = max(0, cursorLine - defaultValue)
                ensureCurrentLine()
            case "B", "e":
                cursorLine += defaultValue
                ensureCurrentLine()
            case "C", "a":
                cursorColumn += defaultValue
            case "D":
                cursorColumn = max(0, cursorColumn - defaultValue)
            case "E":
                if let region = activeScrollRegion() {
                    for _ in 0..<defaultValue {
                        if cursorLine == region.upperBound {
                            scrollUpWithinRegion(1)
                        } else {
                            cursorLine += 1
                        }
                    }
                } else {
                    cursorLine += defaultValue
                }
                cursorColumn = 0
                ensureCurrentLine()
            case "F":
                cursorLine = max(0, cursorLine - defaultValue)
                cursorColumn = 0
                ensureCurrentLine()
            case "G", "`":
                cursorColumn = max(0, defaultValue - 1)
            case "H", "f":
                let row = values.first.flatMap { $0 } ?? 1
                let column = values.dropFirst().first.flatMap { $0 } ?? 1
                if originMode, let region = activeScrollRegion() {
                    cursorLine = min(region.upperBound, region.lowerBound + max(0, row - 1))
                } else {
                    cursorLine = max(0, row - 1)
                }
                cursorColumn = max(0, column - 1)
                ensureCurrentLine()
            case "d":
                let row = values.first.flatMap { $0 } ?? 1
                if originMode, let region = activeScrollRegion() {
                    cursorLine = min(region.upperBound, region.lowerBound + max(0, row - 1))
                } else {
                    cursorLine = max(0, row - 1)
                }
                ensureCurrentLine()
            case "J":
                ensureCurrentLine()
                switch eraseMode {
                case 1:
                    if cursorLine > 0 {
                        for lineIndex in 0..<cursorLine {
                            lines[lineIndex].removeAll()
                        }
                    }
                    while lines[cursorLine].count <= cursorColumn {
                        lines[cursorLine].append(" ")
                    }
                    for index in 0...cursorColumn {
                        lines[cursorLine][index] = " "
                    }
                case 2:
                    lines = [[]]
                    cursorLine = 0
                    cursorColumn = 0
                default:
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine].removeSubrange(cursorColumn...)
                    }
                    if cursorLine + 1 < lines.count {
                        lines.removeSubrange((cursorLine + 1)..<lines.count)
                    }
                }
            case "K":
                ensureCurrentLine()
                switch eraseMode {
                case 1:
                    while lines[cursorLine].count <= cursorColumn {
                        lines[cursorLine].append(" ")
                    }
                    for index in 0...cursorColumn {
                        lines[cursorLine][index] = " "
                    }
                case 2:
                    lines[cursorLine].removeAll()
                default:
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine].removeSubrange(cursorColumn...)
                    }
                }
            case "@":
                ensureCurrentLine()
                let insertCount = max(0, defaultValue)
                guard insertCount > 0 else {
                    break
                }
                while lines[cursorLine].count < cursorColumn {
                    lines[cursorLine].append(" ")
                }
                let blanks = Array(repeating: Character(" "), count: insertCount)
                lines[cursorLine].insert(contentsOf: blanks, at: cursorColumn)
            case "L":
                ensureCurrentLine()
                let insertCount = max(0, defaultValue)
                guard insertCount > 0 else {
                    break
                }
                if activeScrollRegion()?.contains(cursorLine) == true {
                    insertBlankLinesWithinRegion(insertCount, at: cursorLine)
                } else {
                    let blanks = Array(repeating: [Character](), count: insertCount)
                    lines.insert(contentsOf: blanks, at: cursorLine)
                }
            case "M":
                ensureCurrentLine()
                let deleteCount = max(0, defaultValue)
                guard deleteCount > 0 else {
                    break
                }
                if activeScrollRegion()?.contains(cursorLine) == true {
                    deleteLinesWithinRegion(deleteCount, at: cursorLine)
                } else {
                    let endLine = min(lines.count, cursorLine + deleteCount)
                    if cursorLine < endLine {
                        lines.removeSubrange(cursorLine..<endLine)
                    }
                    ensureCurrentLine()
                }
            case "P":
                ensureCurrentLine()
                guard cursorColumn < lines[cursorLine].count else {
                    break
                }
                let endIndex = min(lines[cursorLine].count, cursorColumn + defaultValue)
                lines[cursorLine].removeSubrange(cursorColumn..<endIndex)
            case "S":
                ensureCurrentLine()
                let scrollCount = max(0, defaultValue)
                guard scrollCount > 0 else {
                    break
                }
                if activeScrollRegion() != nil {
                    scrollUpWithinRegion(scrollCount)
                } else {
                    let visibleLineCount = max(lines.count, cursorLine + 1)
                    if scrollCount >= visibleLineCount {
                        lines = Array(repeating: [], count: visibleLineCount)
                    } else {
                        lines.removeFirst(scrollCount)
                        lines.append(contentsOf: Array(repeating: [], count: scrollCount))
                    }
                }
                ensureCurrentLine()
            case "T":
                ensureCurrentLine()
                let scrollCount = max(0, defaultValue)
                guard scrollCount > 0 else {
                    break
                }
                if activeScrollRegion() != nil {
                    scrollDownWithinRegion(scrollCount)
                } else {
                    let visibleLineCount = max(lines.count, cursorLine + 1)
                    if scrollCount >= visibleLineCount {
                        lines = Array(repeating: [], count: visibleLineCount)
                    } else {
                        lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: 0)
                        lines.removeLast(min(scrollCount, lines.count))
                    }
                }
                ensureCurrentLine()
            case "r":
                let requestedTop = max(1, values.first.flatMap { $0 } ?? 1)
                let requestedBottom = max(requestedTop, values.dropFirst().first.flatMap { $0 } ?? terminalRows)
                scrollRegionTop = min(max(0, requestedTop - 1), max(0, terminalRows - 1))
                scrollRegionBottom = min(max(scrollRegionTop, requestedBottom - 1), max(0, terminalRows - 1))
                hasExplicitScrollRegion = true
                cursorLine = 0
                cursorColumn = 0
                ensureCurrentLine()
            case "X":
                ensureCurrentLine()
                let eraseCount = max(0, defaultValue)
                guard eraseCount > 0 else {
                    break
                }
                while lines[cursorLine].count < cursorColumn {
                    lines[cursorLine].append(" ")
                }
                let endIndex = min(lines[cursorLine].count, cursorColumn + eraseCount)
                if cursorColumn < endIndex {
                    for index in cursorColumn..<endIndex {
                        lines[cursorLine][index] = " "
                    }
                }
            case "b":
                guard let repeatedCharacter = lastRenderedCharacter else {
                    break
                }
                for _ in 0..<defaultValue {
                    ensureCurrentLine()
                    if cursorColumn < lines[cursorLine].count {
                        lines[cursorLine][cursorColumn] = repeatedCharacter
                    } else {
                        while lines[cursorLine].count < cursorColumn {
                            lines[cursorLine].append(" ")
                        }
                        lines[cursorLine].append(repeatedCharacter)
                    }
                    cursorColumn += 1
                }
            case "s":
                guard parameters.isEmpty else {
                    break
                }
                savedCursorLine = cursorLine
                savedCursorColumn = cursorColumn
            case "u":
                guard parameters.isEmpty else {
                    break
                }
                cursorLine = savedCursorLine
                cursorColumn = savedCursorColumn
                ensureCurrentLine()
            default:
                break
            }
        }

        while let scalar = iterator.next() {
            switch scalar {
            case "\u{001B}":
                guard let next = iterator.next() else {
                    continue
                }

                if next == "[" {
                    var parameters = ""
                    while let scalar = iterator.next() {
                        if (0x40...0x7E).contains(scalar.value) {
                            parseCSI(finalCharacter: scalar, parameters: parameters)
                            break
                        }
                        parameters.unicodeScalars.append(scalar)
                    }
                } else if next == "]" {
                    skipOperatingSystemCommand()
                } else if next == "P" || next == "X" || next == "^" || next == "_" {
                    skipStringCommand(allowBellTerminator: false)
                } else if next == "(" {
                    if let designator = iterator.next(), let characterSet = characterSet(for: designator) {
                        g0CharacterSet = characterSet
                    }
                } else if next == ")" {
                    if let designator = iterator.next(), let characterSet = characterSet(for: designator) {
                        g1CharacterSet = characterSet
                    }
                } else if next == "7" {
                    savedCursorLine = cursorLine
                    savedCursorColumn = cursorColumn
                } else if next == "8" {
                    cursorLine = savedCursorLine
                    cursorColumn = savedCursorColumn
                    ensureCurrentLine()
                } else if next == "D" {
                    if let region = activeScrollRegion() {
                        if cursorLine == region.upperBound {
                            scrollUpWithinRegion(1)
                        } else {
                            cursorLine += 1
                        }
                    } else {
                        let visibleLineCount = max(lines.count, cursorLine + 1)
                        if cursorLine + 1 < visibleLineCount {
                            cursorLine += 1
                        } else {
                            lines.removeFirst()
                            lines.append([])
                            cursorLine = max(0, visibleLineCount - 1)
                        }
                    }
                    ensureCurrentLine()
                } else if next == "E" {
                    if let region = activeScrollRegion() {
                        if cursorLine == region.upperBound {
                            scrollUpWithinRegion(1)
                        } else {
                            cursorLine += 1
                        }
                    } else {
                        let visibleLineCount = max(lines.count, cursorLine + 1)
                        if cursorLine + 1 < visibleLineCount {
                            cursorLine += 1
                        } else {
                            lines.removeFirst()
                            lines.append([])
                            cursorLine = max(0, visibleLineCount - 1)
                        }
                    }
                    cursorColumn = 0
                    ensureCurrentLine()
                } else if next == "M" {
                    if let region = activeScrollRegion() {
                        if cursorLine == region.lowerBound {
                            scrollDownWithinRegion(1)
                        } else {
                            cursorLine -= 1
                        }
                    } else if cursorLine > 0 {
                        cursorLine -= 1
                    } else {
                        let visibleLineCount = max(lines.count, 1)
                        lines.insert([], at: 0)
                        if lines.count > visibleLineCount {
                            lines.removeLast(lines.count - visibleLineCount)
                        }
                    }
                    ensureCurrentLine()
                } else if next == "c" {
                    lines = [[]]
                    cursorLine = 0
                    cursorColumn = 0
                    cursorVisible = true
                    applicationCursorMode = false
                    originMode = false
                    savedCursorLine = 0
                    savedCursorColumn = 0
                    primaryBufferLines = lines
                    primaryBufferCursorLine = cursorLine
                    primaryBufferCursorColumn = cursorColumn
                    primaryBufferCursorVisible = cursorVisible
                    primaryBufferApplicationCursorMode = applicationCursorMode
                    primaryBufferOriginMode = originMode
                    primaryBufferSavedCursorLine = savedCursorLine
                    primaryBufferSavedCursorColumn = savedCursorColumn
                    usingAlternateBuffer = false
                    scrollRegionTop = 0
                    scrollRegionBottom = max(0, terminalRows - 1)
                    hasExplicitScrollRegion = false
                    primaryBufferScrollRegionTop = scrollRegionTop
                    primaryBufferScrollRegionBottom = scrollRegionBottom
                    primaryBufferHasExplicitScrollRegion = hasExplicitScrollRegion
                    g0CharacterSet = .ascii
                    g1CharacterSet = .ascii
                    usingG1CharacterSet = false
                    lastRenderedCharacter = nil
                    primaryBufferG0CharacterSet = g0CharacterSet
                    primaryBufferG1CharacterSet = g1CharacterSet
                    primaryBufferUsingG1CharacterSet = usingG1CharacterSet
                }
            case "\u{000E}":
                usingG1CharacterSet = true
            case "\u{000F}":
                usingG1CharacterSet = false
            case "\u{0007}":
                continue
            case "\u{0090}", "\u{0098}", "\u{009E}", "\u{009F}":
                skipStringCommand(allowBellTerminator: false)
            case "\u{009D}":
                skipStringCommand(allowBellTerminator: true)
            case "\r":
                cursorColumn = 0
            case "\u{8}":
                guard cursorColumn > 0 else {
                    continue
                }
                cursorColumn -= 1
            case "\u{7F}":
                guard cursorColumn > 0 else {
                    continue
                }
                ensureCurrentLine()
                cursorColumn -= 1
                if cursorColumn < lines[cursorLine].count {
                    lines[cursorLine].remove(at: cursorColumn)
                }
            case "\n":
                if let region = activeScrollRegion() {
                    if cursorLine == region.upperBound {
                        scrollUpWithinRegion(1)
                    } else {
                        cursorLine += 1
                    }
                } else {
                    cursorLine += 1
                }
                cursorColumn = 0
                ensureCurrentLine()
            case "\t":
                ensureCurrentLine()
                let tabWidth = 8
                let nextTabStop = ((cursorColumn / tabWidth) + 1) * tabWidth
                while lines[cursorLine].count < nextTabStop {
                    lines[cursorLine].append(" ")
                }
                cursorColumn = nextTabStop
            default:
                let character = renderedCharacter(for: scalar)
                ensureCurrentLine()
                if cursorColumn < lines[cursorLine].count {
                    lines[cursorLine][cursorColumn] = character
                } else {
                    while lines[cursorLine].count < cursorColumn {
                        lines[cursorLine].append(" ")
                    }
                    lines[cursorLine].append(character)
                }
                cursorColumn += 1
                lastRenderedCharacter = character
            }
        }

        let renderedLines = lines.map { String($0) }
        let normalizedTranscript = renderedLines.joined(separator: "\n")
        let viewport = Self.makeViewport(
            lines: renderedLines,
            cursorLine: cursorLine,
            cursorColumn: cursorColumn,
            terminalColumns: terminalColumns,
            terminalRows: terminalRows,
            transcript: normalizedTranscript
        )

        return (
            transcript: viewport.transcript,
            visibleLines: viewport.visibleLines,
            cursorRow: viewport.cursorRow,
            cursorColumn: viewport.cursorColumn,
            cursorVisible: cursorVisible,
            applicationCursorMode: applicationCursorMode
        )
    }

    private static func makeViewport(
        lines: [String],
        cursorLine: Int,
        cursorColumn: Int,
        terminalColumns: Int,
        terminalRows: Int,
        transcript: String
    ) -> (transcript: String, visibleLines: [String], cursorRow: Int, cursorColumn: Int) {
        let columns = max(1, terminalColumns)
        let rows = max(1, terminalRows)
        let sourceLines = lines.isEmpty ? [""] : lines
        var wrappedLines: [String] = []
        var cursorWrappedRow = 0
        var cursorWrappedColumn = 0

        for (lineIndex, line) in sourceLines.enumerated() {
            let segments: [String]
            if line.isEmpty {
                segments = [""]
            } else {
                var builtSegments: [String] = []
                var startIndex = line.startIndex
                while startIndex < line.endIndex {
                    let endIndex = line.index(startIndex, offsetBy: columns, limitedBy: line.endIndex) ?? line.endIndex
                    builtSegments.append(String(line[startIndex..<endIndex]))
                    startIndex = endIndex
                }
                segments = builtSegments
            }

            let baseWrappedRow = wrappedLines.count
            wrappedLines.append(contentsOf: segments)

            if lineIndex == cursorLine {
                let segmentIndex = min(max(cursorColumn / columns, 0), max(segments.count - 1, 0))
                cursorWrappedRow = baseWrappedRow + segmentIndex
                cursorWrappedColumn = min(cursorColumn - (segmentIndex * columns), columns)
            }
        }

        let visibleStartIndex = max(0, wrappedLines.count - rows)
        let visibleLines = Array(wrappedLines.suffix(rows))
        let cursorRow = max(0, cursorWrappedRow - visibleStartIndex)

        return (
            transcript: transcript,
            visibleLines: visibleLines,
            cursorRow: cursorRow,
            cursorColumn: cursorWrappedColumn
        )
    }

    private func resolveNamedSessionName(_ requestedName: String?, existingSessions: [Session]) -> String {
        if let trimmedName = requestedName?.trimmingCharacters(in: .whitespacesAndNewlines), trimmedName.isEmpty == false {
            return trimmedName
        }

        return "Session \(existingSessions.filter { $0.isDefault == false }.count + 1)"
    }

    private func defaultSessionSummary(for workspace: Workspace, providerID: ProviderID) throws -> ProviderDefaultSessionSummary {
        guard let session = try metadataStore.defaultSession(workspaceID: workspace.id, providerID: providerID) else {
            return ProviderDefaultSessionSummary(
                state: .notCreated,
                summary: "No default session yet",
                actionTitle: "Launch"
            )
        }

        let resolvedSession = try reconcileSessionRuntimeState(session)

        switch resolvedSession.state {
        case .ready:
            return ProviderDefaultSessionSummary(
                state: .ready,
                summary: "Default session ready",
                actionTitle: "Resume",
                sessionID: resolvedSession.id
            )
        case .interrupted:
            return ProviderDefaultSessionSummary(
                state: .interrupted,
                summary: resolvedSession.failureMessage ?? "Session interrupted after the service restarted",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        case .exited:
            return ProviderDefaultSessionSummary(
                state: .exited,
                summary: resolvedSession.failureMessage ?? "Session exited",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        case .failed:
            return ProviderDefaultSessionSummary(
                state: .failed,
                summary: resolvedSession.failureMessage ?? "Last launch failed",
                actionTitle: "Relaunch",
                sessionID: resolvedSession.id
            )
        }
    }

    private func reconcileSessionRuntimeState(_ session: Session) throws -> Session {
        guard session.state == .ready else {
            return session
        }

        if let runtimeState = sessionRuntimeManager.runtimeState(for: session) {
            guard runtimeState != .ready else {
                return session
            }

            return try updatedSessionForRuntimeState(session, runtimeState: runtimeState)
        }

        guard sessionRuntimeManager.hasRuntime(for: session) == false else {
            return session
        }

        let workspace = try metadataStore.workspace(id: session.workspaceID)
        if try sessionMayRemainReadyWithoutRuntime(session, workspace: workspace) {
            return session
        }

        return try metadataStore.updateSession(
            id: session.id,
            state: .interrupted,
            failureMessage: try interruptedSessionFailureMessage(for: session, workspace: workspace)
        )
    }

    private func sessionMayRemainReadyWithoutRuntime(_ session: Session, workspace: Workspace?) throws -> Bool {
        guard try stopRequiresActiveIBMBobTurn(session, workspace: workspace) else {
            return false
        }

        return try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)?.ibmBobTurnInProgress != true
    }

    private func readySessionRecordMayBeDeleted(_ session: Session) throws -> Bool {
        guard session.state == .ready,
              let workspace = try metadataStore.workspace(id: session.workspaceID),
              try stopRequiresActiveIBMBobTurn(session, workspace: workspace) else {
            return false
        }

        if let runtimeLinkage = sessionRuntimeManager.sessionRecordAdapterMetadata(for: session)?.ibmBobSessionLinkage {
            return runtimeLinkage.turnInProgress == false
        }

        return try metadataStore.sessionRecordAdapterMetadata(sessionID: session.id)?.ibmBobTurnInProgress != true
    }

    private func stopRequiresActiveIBMBobTurn(_ session: Session, workspace: Workspace? = nil) throws -> Bool {
        let resolvedWorkspace = if let workspace {
            workspace
        } else {
            try metadataStore.workspace(id: session.workspaceID)
        }

        guard session.providerID == .ibmBob else {
            return false
        }

        return try persistedPrimarySurface(for: session, workspace: resolvedWorkspace) == .structuredActivityFeed
    }

    private func interruptedSessionFailureMessage(for session: Session, workspace: Workspace?) throws -> String {
        if try persistedPrimarySurface(for: session, workspace: workspace) == .structuredActivityFeed,
           session.providerID == .ibmBob || workspace?.kind == .local {
            return structuredInterruptedSessionFailureMessage(for: session.providerID)
        }

        return "Session interrupted because the background service restarted. Relaunch to create a new live runtime."
    }
}

extension NexusService: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let bridge = NexusXPCBridge(service: self, connection: newConnection)
        newConnection.exportedInterface = NSXPCInterface(with: NexusXPCProtocol.self)
        newConnection.exportedObject = bridge
        newConnection.remoteObjectInterface = NSXPCInterface(with: NexusSessionScreenObserverXPCProtocol.self)
        newConnection.invalidationHandler = { [weak bridge] in
            bridge?.invalidate()
        }
        newConnection.interruptionHandler = { [weak bridge] in
            bridge?.invalidate()
        }
        newConnection.resume()
        return true
    }
}

private final class NexusXPCBridge: NSObject, NexusXPCProtocol, @unchecked Sendable {
    let service: NexusService
    private let connection: NSXPCConnection
    private let lock = NSLock()
    private var observationIDs: Set<UUID> = []

    init(service: NexusService, connection: NSXPCConnection) {
        self.service = service
        self.connection = connection
    }

    func invalidate() {
        let activeObservationIDs: [UUID]
        lock.lock()
        activeObservationIDs = Array(observationIDs)
        observationIDs.removeAll()
        lock.unlock()

        for observationID in activeObservationIDs {
            service.cancelSessionScreenObservation(observationID: observationID)
        }
    }

    func getServiceStatus(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { service.serviceStatus() }, reply: reply)
    }

    func listWorkspaceGroups(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listWorkspaceGroups, reply: reply)
    }

    func createWorkspaceGroup(name: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.createWorkspaceGroup(name: name) }, reply: reply)
    }

    func listWorkspaces(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listWorkspaces, reply: reply)
    }

    func listHosts(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listHosts, reply: reply)
    }

    func getHostDetail(hostID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.getHostDetail(hostID: resolveUUID(hostID)) }, reply: reply)
    }

    func createHost(name: String, sshTarget: String, port: NSNumber?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.createHost(name: name, sshTarget: sshTarget, port: port?.intValue) }, reply: reply)
    }

    func updateHost(hostID: String, name: String, sshTarget: String, port: NSNumber?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.updateHost(hostID: resolveUUID(hostID), name: name, sshTarget: sshTarget, port: port?.intValue) }, reply: reply)
    }

    func validateHost(hostID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.validateHost(hostID: resolveUUID(hostID)) }, reply: reply)
    }

    func deleteHost(hostID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.deleteHost(hostID: resolveUUID(hostID)) }, reply: reply)
    }

    func listRecentNavigation(limit: Int, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.listRecentNavigation(limit: limit) }, reply: reply)
    }

    func getRemoteAccessState(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.remoteAccessState, reply: reply)
    }

    func setRemoteAccessEnabled(isEnabled: Bool, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { service.setRemoteAccessEnabled(isEnabled) }, reply: reply)
    }

    func startPairing(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.startPairing, reply: reply)
    }

    func completePairing(pairingCode: String, deviceName: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.completePairing(pairingCode: pairingCode, deviceName: deviceName) }, reply: reply)
    }

    func listPairedDevices(_ reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: service.listPairedDevices, reply: reply)
    }

    func revokePairedDevice(deviceID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.revokePairedDevice(deviceID: resolveUUID(deviceID)) }, reply: reply)
    }

    func recordNavigation(targetPayload: Data, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                let target = try JSONDecoder().decode(NavigationTarget.self, from: targetPayload)
                try service.recordNavigation(target: target)
                return true
            },
            reply: reply
        )
    }

    func searchNavigation(query: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.searchNavigation(query: query) }, reply: reply)
    }

    func recordRemoteClientDiagnosticBreadcrumb(payload: Data, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                let breadcrumb = try JSONDecoder().decode(RemoteClientDiagnosticBreadcrumb.self, from: payload)
                try service.recordRemoteClientDiagnosticBreadcrumb(breadcrumb)
                return true
            },
            reply: reply
        )
    }

    func getWorkspaceOverview(workspaceID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { [self] in try await self.service.getWorkspaceOverview(workspaceID: self.resolveUUID(workspaceID)) }, reply: reply)
    }

    func getProviderDetail(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedProviderID = ProviderID(rawValue: providerID) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.getProviderDetail(
                    workspaceID: self.resolveUUID(workspaceID),
                    providerID: resolvedProviderID
                )
            },
            reply: reply
        )
    }

    func createLocalWorkspace(name: String?, folderPath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                try service.createLocalWorkspace(
                    name: name,
                    folderPath: folderPath,
                    primaryGroupID: try primaryGroupID.map(resolveUUID)
                )
            },
            reply: reply
        )
    }

    func createRemoteWorkspace(name: String?, hostID: String, remotePath: String, primaryGroupID: String?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                try service.createRemoteWorkspace(
                    name: name,
                    hostID: resolveUUID(hostID),
                    remotePath: remotePath,
                    primaryGroupID: try primaryGroupID.map(resolveUUID)
                )
            },
            reply: reply
        )
    }

    func launchOrResumeDefaultSession(workspaceID: String, providerID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedProviderID = ProviderID(rawValue: providerID) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.launchOrResumeDefaultSession(
                    workspaceID: self.resolveUUID(workspaceID),
                    providerID: resolvedProviderID
                )
            },
            reply: reply
        )
    }

    func launchOrResumeSession(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { [self] in try await self.service.launchOrResumeSession(sessionID: self.resolveUUID(sessionID)) }, reply: reply)
    }

    func createNamedSession(workspaceID: String, providerID: String, name: String?, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedProviderID = ProviderID(rawValue: providerID) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.createNamedSession(
                    workspaceID: self.resolveUUID(workspaceID),
                    providerID: resolvedProviderID,
                    name: name
                )
            },
            reply: reply
        )
    }

    func stopSession(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.stopSession(sessionID: resolveUUID(sessionID)) }, reply: reply)
    }

    func deleteSessionRecord(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.deleteSessionRecord(sessionID: resolveUUID(sessionID)) }, reply: reply)
    }

    func getSessionRecord(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.getSessionRecord(sessionID: resolveUUID(sessionID)) }, reply: reply)
    }

    func getSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(with: { try service.getSessionScreen(sessionID: resolveUUID(sessionID)) }, reply: reply)
    }

    func observeSessionScreen(sessionID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? NexusSessionScreenObserverXPCProtocol else {
                    throw CocoaError(.coderInvalidValue)
                }

                let observationID = UUID()
                let screenObserver = SessionScreenObserverProxy(observer: observer, observationID: observationID)
                let start = try service.observeSessionScreen(observationID: observationID, sessionID: resolveUUID(sessionID)) { screen in
                    screenObserver.send(screen)
                }

                lock.lock()
                observationIDs.insert(start.observationID)
                lock.unlock()
                return start
            },
            reply: reply
        )
    }

    func cancelSessionScreenObservation(observationID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                let resolvedObservationID = try resolveUUID(observationID)
                service.cancelSessionScreenObservation(observationID: resolvedObservationID)
                lock.lock()
                observationIDs.remove(resolvedObservationID)
                lock.unlock()
                return true
            },
            reply: reply
        )
    }

    func sendSessionInput(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in try await self.service.sendSessionInput(sessionID: self.resolveUUID(sessionID), text: text) },
            reply: reply
        )
    }

    func sendSessionText(sessionID: String, text: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in try await self.service.sendSessionText(sessionID: self.resolveUUID(sessionID), text: text) },
            reply: reply
        )
    }

    func sendSessionInputKey(sessionID: String, key: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedKey = SessionInputKey(rawValue: key) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.sendSessionInputKey(sessionID: self.resolveUUID(sessionID), key: resolvedKey)
            },
            reply: reply
        )
    }

    func respondToApprovalRequest(sessionID: String, approvalRequestID: String, decision: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedDecision = ApprovalRequestDecision(rawValue: decision) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.respondToApprovalRequest(
                    sessionID: self.resolveUUID(sessionID),
                    approvalRequestID: self.resolveUUID(approvalRequestID),
                    decision: resolvedDecision
                )
            },
            reply: reply
        )
    }

    func resizeSession(sessionID: String, columns: Int, rows: Int, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in try await self.service.resizeSession(sessionID: self.resolveUUID(sessionID), columns: columns, rows: rows) },
            reply: reply
        )
    }

    func takeRemoteSessionControl(sessionID: String, pairedDeviceID: String, columns: Int, rows: Int, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                try await self.service.takeRemoteSessionControl(
                    sessionID: self.resolveUUID(sessionID),
                    pairedDeviceID: self.resolveUUID(pairedDeviceID),
                    columns: columns,
                    rows: rows
                )
            },
            reply: reply
        )
    }

    func releaseRemoteSessionControl(sessionID: String, pairedDeviceID: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: {
                try service.releaseRemoteSessionControl(
                    sessionID: resolveUUID(sessionID),
                    pairedDeviceID: resolveUUID(pairedDeviceID)
                )
            },
            reply: reply
        )
    }

    func sendRemoteSessionInput(sessionID: String, pairedDeviceID: String, text: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                try await self.service.sendRemoteSessionInput(
                    sessionID: self.resolveUUID(sessionID),
                    pairedDeviceID: self.resolveUUID(pairedDeviceID),
                    text: text
                )
            },
            reply: reply
        )
    }

    func respondToRemoteApprovalRequest(sessionID: String, pairedDeviceID: String, approvalRequestID: String, decision: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedDecision = ApprovalRequestDecision(rawValue: decision) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.respondToRemoteApprovalRequest(
                    sessionID: self.resolveUUID(sessionID),
                    pairedDeviceID: self.resolveUUID(pairedDeviceID),
                    approvalRequestID: self.resolveUUID(approvalRequestID),
                    decision: resolvedDecision
                )
            },
            reply: reply
        )
    }

    func sendRemoteSessionText(sessionID: String, pairedDeviceID: String, text: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                try await self.service.sendRemoteSessionText(
                    sessionID: self.resolveUUID(sessionID),
                    pairedDeviceID: self.resolveUUID(pairedDeviceID),
                    text: text
                )
            },
            reply: reply
        )
    }

    func sendRemoteSessionInputKey(sessionID: String, pairedDeviceID: String, key: String, reply: @escaping (Data?, NSString?) -> Void) {
        sendReply(
            with: { [self] in
                guard let resolvedKey = SessionInputKey(rawValue: key) else {
                    throw CocoaError(.coderInvalidValue)
                }

                return try await self.service.sendRemoteSessionInputKey(
                    sessionID: self.resolveUUID(sessionID),
                    pairedDeviceID: self.resolveUUID(pairedDeviceID),
                    key: resolvedKey
                )
            },
            reply: reply
        )
    }

    private func sendReply<T: Encodable>(with operation: () throws -> T, reply: @escaping (Data?, NSString?) -> Void) {
        do {
            let payload = try JSONEncoder().encode(operation())
            reply(payload, nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    private func sendReply<T: Encodable>(with operation: @escaping @Sendable () async throws -> T, reply: @escaping (Data?, NSString?) -> Void) {
        let relay = XPCReplyRelay(reply)
        let replyOperation = AsyncEncodedReplyOperation(operation: operation, replyRelay: relay)
        Task(priority: .userInitiated, operation: replyOperation.run)
    }

    private func resolveUUID(_ rawValue: String) throws -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        return uuid
    }
}

private final class XPCReplyRelay: @unchecked Sendable {
    private let reply: (Data?, NSString?) -> Void

    init(_ reply: @escaping (Data?, NSString?) -> Void) {
        self.reply = reply
    }

    func succeed(_ payload: Data) {
        reply(payload, nil)
    }

    func fail(_ error: Error) {
        reply(nil, error.localizedDescription as NSString)
    }
}

private struct AsyncEncodedReplyOperation<T: Encodable>: @unchecked Sendable {
    let operation: @Sendable () async throws -> T
    let replyRelay: XPCReplyRelay

    func run() async {
        do {
            let value = try await operation()
            let payload = try JSONEncoder().encode(value)
            replyRelay.succeed(payload)
        } catch {
            replyRelay.fail(error)
        }
    }
}

private final class SessionScreenObserverProxy: @unchecked Sendable {
    private let observer: any NexusSessionScreenObserverXPCProtocol
    private let observationID: UUID

    init(observer: any NexusSessionScreenObserverXPCProtocol, observationID: UUID) {
        self.observer = observer
        self.observationID = observationID
    }

    func send(_ screen: SessionScreen) {
        guard let payload = try? JSONEncoder().encode(screen) else {
            return
        }

        observer.sessionScreenDidUpdate(observationID: observationID.uuidString, payload: payload)
    }
}
#else
import Foundation

public protocol NexusEmbeddedServiceSession: AnyObject {}

public enum NexusEmbeddedServiceBootstrap {
    public static func bootstrap() throws -> any NexusEmbeddedServiceSession {
        throw NSError(domain: "NexusService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nexus embedded services are only available on macOS"])
    }

    public static func bootstrapForTests() throws -> any NexusEmbeddedServiceSession {
        throw NSError(domain: "NexusService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nexus embedded services are only available on macOS"])
    }

    public static func bootstrapForTests(rootURL: URL) throws -> any NexusEmbeddedServiceSession {
        throw NSError(domain: "NexusService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nexus embedded services are only available on macOS"])
    }
}

@available(iOS, unavailable, message: "NexusService is only available on macOS")
public final class NexusService: NSObject {}
#endif
