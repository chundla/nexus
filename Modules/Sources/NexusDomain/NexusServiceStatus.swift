import Foundation

public struct NexusServiceStatus: Codable, Equatable, Sendable {
    public let state: State
    public let store: MetadataStore

    public init(state: State, store: MetadataStore) {
        self.state = state
        self.store = store
    }

    public enum State: String, Codable, Sendable {
        case running
    }

    public struct MetadataStore: Codable, Equatable, Sendable {
        public let kind: Kind
        public let owner: Owner
        public let location: URL

        public init(kind: Kind, owner: Owner, location: URL) {
            self.kind = kind
            self.owner = owner
            self.location = location
        }

        public enum Kind: String, Codable, Sendable {
            case sqlite
        }

        public enum Owner: String, Codable, Sendable {
            case backgroundService
        }
    }
}
