#if os(macOS)
    import Foundation
    #if canImport(Darwin)
        import Darwin
    #endif

    /// A `PreToolUse` permission request relayed from a `claude` child process via the hook command
    /// configured in `ClaudeApprovalHookBridge.settingsJSON` (see `docs/agents/claude-stream-json-protocol.md` §6).
    struct ClaudeApprovalHookRequest: Sendable {
        let id: String
        let toolName: String
        let toolInputPreview: String?
    }

    enum ClaudeApprovalHookDecision: String, Sendable {
        case allow
        case deny
    }

    enum ClaudeApprovalHookBridgeError: LocalizedError {
        case socketCreationFailed
        case socketPathTooLong
        case bindFailed
        case listenFailed
        case requestNotOpen

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed: "Could not create the Claude approval hook socket."
            case .socketPathTooLong: "The Claude approval hook socket path is too long."
            case .bindFailed: "Could not bind the Claude approval hook socket."
            case .listenFailed: "Could not listen on the Claude approval hook socket."
            case .requestNotOpen: "That Claude approval hook request is no longer open."
            }
        }
    }

    protocol ClaudeApprovalHookBridging: AnyObject {
        var settingsJSON: String { get }
        func setRequestHandler(_ handler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?)
        func start() throws
        func resolve(requestID: String, decision: ClaudeApprovalHookDecision, reason: String) throws
        func stop()
    }

    /// Bridges Claude's `PreToolUse` hook contract to Nexus's Approval Request lifecycle: a `claude` child
    /// process invokes the hook command (`/usr/bin/nc -U <socketPath>`) configured via `settingsJSON`, which
    /// pipes the hook's stdin/stdout to this listener over a Unix domain socket while it blocks for a decision.
    final class ClaudeApprovalHookBridge: ClaudeApprovalHookBridging, @unchecked Sendable {
        private let socketPath: String
        private let lock = NSLock()
        private var listenerSocket: Int32 = -1
        private var requestHandler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?
        private var openConnections: [String: Int32] = [:]
        private var isStopped = false

        var settingsJSON: String {
            let command = "/usr/bin/nc -U \(socketPath)"
            let payload: [String: Any] = [
                "hooks": [
                    "PreToolUse": [
                        ["hooks": [["type": "command", "command": command]]]
                    ]
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8)
            else {
                return "{}"
            }
            return json
        }

        init(socketPath: String = ClaudeApprovalHookBridge.makeDefaultSocketPath()) {
            self.socketPath = socketPath
        }

        /// `sockaddr_un.sun_path` is limited to 104 bytes on macOS, so the default path uses `/tmp` directly
        /// rather than `NSTemporaryDirectory()` (which is long enough under sandboxed/per-user temp dirs to overflow it).
        static func makeDefaultSocketPath() -> String {
            "/tmp/nx-claude-hook-\(UUID().uuidString.prefix(8)).sock"
        }

        func setRequestHandler(_ handler: (@Sendable (ClaudeApprovalHookRequest) -> Void)?) {
            lock.lock()
            requestHandler = handler
            lock.unlock()
        }

        func start() throws {
            unlink(socketPath)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw ClaudeApprovalHookBridgeError.socketCreationFailed
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8)
            guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                close(fd)
                throw ClaudeApprovalHookBridgeError.socketPathTooLong
            }
            withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
                let buffer = rawBuffer.bindMemory(to: Int8.self)
                for (index, byte) in pathBytes.enumerated() {
                    buffer[index] = Int8(bitPattern: byte)
                }
                buffer[pathBytes.count] = 0
            }

            let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bindResult = withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(fd, sockaddrPointer, addressSize)
                }
            }
            guard bindResult == 0 else {
                close(fd)
                throw ClaudeApprovalHookBridgeError.bindFailed
            }
            guard listen(fd, 8) == 0 else {
                close(fd)
                throw ClaudeApprovalHookBridgeError.listenFailed
            }

            lock.lock()
            listenerSocket = fd
            lock.unlock()

            let acceptThread = Thread { [weak self] in
                self?.runAcceptLoop()
            }
            acceptThread.start()
        }

        func resolve(requestID: String, decision: ClaudeApprovalHookDecision, reason: String) throws {
            lock.lock()
            guard let clientSocket = openConnections.removeValue(forKey: requestID) else {
                lock.unlock()
                throw ClaudeApprovalHookBridgeError.requestNotOpen
            }
            lock.unlock()

            let payload: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision.rawValue,
                    "permissionDecisionReason": reason,
                ]
            ]
            defer { close(clientSocket) }
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                return
            }
            _ = data.withUnsafeBytes { write(clientSocket, $0.baseAddress, $0.count) }
        }

        func stop() {
            lock.lock()
            isStopped = true
            let listenerSocketToClose = listenerSocket
            listenerSocket = -1
            let openClientSockets = Array(openConnections.values)
            openConnections.removeAll()
            lock.unlock()

            for clientSocket in openClientSockets {
                close(clientSocket)
            }
            if listenerSocketToClose >= 0 {
                close(listenerSocketToClose)
            }
            unlink(socketPath)
        }

        deinit {
            stop()
        }

        private func runAcceptLoop() {
            while true {
                lock.lock()
                let listenerSocketToAcceptOn = listenerSocket
                lock.unlock()
                guard listenerSocketToAcceptOn >= 0 else {
                    return
                }

                let clientSocket = accept(listenerSocketToAcceptOn, nil, nil)
                guard clientSocket >= 0 else {
                    lock.lock()
                    let stopped = isStopped
                    lock.unlock()
                    if stopped {
                        return
                    }
                    continue
                }
                handleConnection(clientSocket)
            }
        }

        private func handleConnection(_ clientSocket: Int32) {
            var requestData = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                guard bytesRead > 0 else {
                    break
                }
                requestData.append(buffer, count: bytesRead)
            }

            guard let object = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
                close(clientSocket)
                return
            }

            let requestID = UUID().uuidString
            let toolName = (object["tool_name"] as? String) ?? "Tool"
            let toolInputPreview = Self.toolInputPreview(object["tool_input"])

            lock.lock()
            openConnections[requestID] = clientSocket
            let handler = requestHandler
            lock.unlock()

            handler?(ClaudeApprovalHookRequest(id: requestID, toolName: toolName, toolInputPreview: toolInputPreview))
        }

        private static func toolInputPreview(_ input: Any?) -> String? {
            guard let input = input as? [String: Any], input.isEmpty == false else {
                return nil
            }
            if let path = input["file_path"] as? String {
                return path
            }
            if let command = input["command"] as? String {
                return command
            }
            guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
                let json = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return json.count > 120 ? String(json.prefix(120)) + "…" : json
        }
    }
#endif
