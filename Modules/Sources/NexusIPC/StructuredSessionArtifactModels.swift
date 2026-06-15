import Foundation

/// Session-scoped file bytes read on the **Host** for Remote Client download (#243).
public struct StructuredSessionArtifactFile: Codable, Equatable, Sendable {
    public let fileName: String
    public let contentType: String
    public let data: Data

    public init(fileName: String, contentType: String, data: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}
