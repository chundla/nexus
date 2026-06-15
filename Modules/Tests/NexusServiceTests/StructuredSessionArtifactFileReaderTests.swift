import Foundation
@testable import NexusService
import Testing

struct StructuredSessionArtifactFileReaderTests {
    @Test func readArtifactReturnsFileBytesForAbsolutePath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-artifact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("export.html")
        let payload = Data("<html>ok</html>".utf8)
        try payload.write(to: fileURL)

        let artifact = try StructuredSessionArtifactFileReader.read(hostPath: fileURL.path)

        #expect(artifact.fileName == "export.html")
        #expect(artifact.contentType == "text/html")
        #expect(artifact.data == payload)
    }

    @Test func readArtifactRejectsRelativePaths() {
        #expect(throws: StructuredSessionArtifactFileReaderError.invalidPath) {
            _ = try StructuredSessionArtifactFileReader.read(hostPath: "tmp/export.html")
        }
    }

    @Test func readArtifactRejectsParentTraversal() {
        #expect(throws: StructuredSessionArtifactFileReaderError.invalidPath) {
            _ = try StructuredSessionArtifactFileReader.read(hostPath: "/tmp/../etc/passwd")
        }
    }
}