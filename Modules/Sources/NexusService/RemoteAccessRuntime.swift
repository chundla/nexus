import Foundation
import NexusDomain

final class RemoteAccessRuntime {
    private let lock = NSLock()
    private var isEnabled = false
    private var activePairing: PairingCeremony?

    func state(now: Date = Date()) -> RemoteAccessState {
        lock.lock()
        defer { lock.unlock() }
        expirePairingIfNeeded(now: now)
        return RemoteAccessState(isEnabled: isEnabled, activePairing: activePairing)
    }

    func setEnabled(_ enabled: Bool, now: Date = Date()) -> RemoteAccessState {
        lock.lock()
        defer { lock.unlock() }
        isEnabled = enabled
        expirePairingIfNeeded(now: now)
        if enabled == false {
            activePairing = nil
        }
        return RemoteAccessState(isEnabled: isEnabled, activePairing: activePairing)
    }

    func startPairing(now: Date = Date()) throws -> PairingCeremony {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled else {
            throw NexusRemoteAccessError.remoteAccessDisabled
        }

        expirePairingIfNeeded(now: now)
        let code = Self.makePairingCode()
        let ceremony = PairingCeremony(
            id: UUID(),
            code: code,
            qrPayload: "nexus://pair?code=\(code)",
            createdAt: now,
            expiresAt: now.addingTimeInterval(10 * 60)
        )
        activePairing = ceremony
        return ceremony
    }

    func completePairing(code: String, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled else {
            throw NexusRemoteAccessError.remoteAccessDisabled
        }

        expirePairingIfNeeded(now: now)
        guard activePairing?.code == code else {
            throw NexusRemoteAccessError.pairingCodeNotFound
        }

        activePairing = nil
    }

    private func expirePairingIfNeeded(now: Date) {
        if let activePairing, activePairing.expiresAt <= now {
            self.activePairing = nil
        }
    }

    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

enum NexusRemoteAccessError: LocalizedError {
    case remoteAccessDisabled
    case pairingCodeNotFound

    var errorDescription: String? {
        switch self {
        case .remoteAccessDisabled:
            "Enable Remote Access before starting Pairing"
        case .pairingCodeNotFound:
            "The Pairing code is no longer valid"
        }
    }
}
