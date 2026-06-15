import Foundation
import NexusIPC

enum StructuredSessionArtifactFileReaderError: LocalizedError, Equatable {
    case invalidPath
    case pathNotFound
    case pathNotAFile
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "Artifact path is not allowed."
        case .pathNotFound:
            "Artifact file was not found on the Host."
        case .pathNotAFile:
            "Artifact path does not refer to a file."
        case .fileTooLarge:
            "Artifact file is too large to download."
        }
    }
}

/// Reads provider-native structured artifacts from the Mac **Host** filesystem (#243).
enum StructuredSessionArtifactFileReader {
    static let maxDownloadBytes = 50 * 1024 * 1024

    static func read(hostPath: String) throws -> StructuredSessionArtifactFile {
        let trimmed = hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              trimmed.contains("..") == false else {
            throw StructuredSessionArtifactFileReaderError.invalidPath
        }

        let url = URL(fileURLWithPath: trimmed, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw StructuredSessionArtifactFileReaderError.pathNotFound
        }
        guard isDirectory.boolValue == false else {
            throw StructuredSessionArtifactFileReaderError.pathNotAFile
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxDownloadBytes else {
            throw StructuredSessionArtifactFileReaderError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let fileName = url.lastPathComponent
        let contentType = structuredSessionArtifactContentType(for: url.pathExtension)

        return StructuredSessionArtifactFile(
            fileName: fileName,
            contentType: contentType,
            data: data
        )
    }

    private static func structuredSessionArtifactContentType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm":
            "text/html"
        case "json":
            "application/json"
        case "md", "markdown":
            "text/markdown"
        case "txt":
            "text/plain"
        case "pdf":
            "application/pdf"
        default:
            "application/octet-stream"
        }
    }
}