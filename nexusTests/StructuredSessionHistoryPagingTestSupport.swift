#if os(macOS)
import Foundation
@testable import NexusService

final class HistoryPagingPiRPCTransport: PiRPCTransporting, @unchecked Sendable {
    private let messages: [[String: Any]]
    private var stdoutLineHandler: (@Sendable (String) -> Void)?
    private var terminationHandler: (@Sendable (Int32) -> Void)?

    init(messages: [[String: Any]]) {
        self.messages = messages
    }

    func setStdoutLineHandler(_ handler: (@Sendable (String) -> Void)?) {
        stdoutLineHandler = handler
    }

    func setTerminationHandler(_ handler: (@Sendable (Int32) -> Void)?) {
        terminationHandler = handler
    }

    func start() throws {}

    func sendLine(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        switch type {
        case "get_state":
            emit([
                "id": object["id"] as? String ?? "state",
                "type": "response",
                "command": "get_state",
                "success": true,
                "data": ["sessionId": "pi-session-1"]
            ])
        case "get_commands":
            emit([
                "id": object["id"] as? String ?? "commands",
                "type": "response",
                "command": "get_commands",
                "success": true,
                "data": ["commands": []]
            ])
        case "get_available_models":
            emit([
                "id": object["id"] as? String ?? "available-models",
                "type": "response",
                "command": "get_available_models",
                "success": true,
                "data": ["models": []]
            ])
        case "get_fork_messages":
            emit([
                "id": object["id"] as? String ?? "fork-messages",
                "type": "response",
                "command": "get_fork_messages",
                "success": true,
                "data": ["messages": []]
            ])
        case "get_messages":
            emit([
                "id": object["id"] as? String ?? "messages",
                "type": "response",
                "command": "get_messages",
                "success": true,
                "data": ["messages": messages]
            ])
        default:
            return
        }
    }

    func terminate() throws {
        terminationHandler?(0)
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        stdoutLineHandler?(line)
    }
}
#endif
