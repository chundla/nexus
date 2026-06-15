import Foundation

/// Markdown `![alt](url)` reference extracted from structured feed assistant/reasoning copy (#242).
public struct StructuredSessionFeedMarkdownImageReference: Equatable, Sendable {
    public let altText: String
    public let urlString: String

    public init(altText: String, urlString: String) {
        self.altText = altText
        self.urlString = urlString
    }
}

/// One inline text run or image preview slot in feed markdown (#242).
public enum StructuredSessionFeedMarkdownBodySegment: Equatable, Sendable {
    case text(String)
    case image(StructuredSessionFeedMarkdownImageReference)
}

/// Remote Client: only fetch remote http(s) image URLs in the structured feed; no file/data schemes (#242).
public enum StructuredSessionFeedRemoteClientImageURLPolicy {
    public static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }
}

public func structuredSessionFeedMarkdownImageReferences(
    in markdown: String
) -> [StructuredSessionFeedMarkdownImageReference] {
    structuredSessionFeedMarkdownBodySegments(in: markdown).compactMap { segment in
        guard case .image(let ref) = segment else {
            return nil
        }
        return ref
    }
}

public func structuredSessionFeedMarkdownBodySegments(
    in markdown: String
) -> [StructuredSessionFeedMarkdownBodySegment] {
    guard markdown.isEmpty == false else {
        return []
    }

    var segments: [StructuredSessionFeedMarkdownBodySegment] = []
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    var isInsideFencedCodeBlock = false
    var textBuffer = ""

    func flushTextBuffer() {
        guard textBuffer.isEmpty == false else {
            return
        }
        segments.append(.text(textBuffer))
        textBuffer = ""
    }

    for lineIndex in lines.indices {
        let line = String(lines[lineIndex])
        if lineIndex > lines.startIndex, isInsideFencedCodeBlock == false {
            textBuffer.append("\n")
        }
        let isDelimiter = structuredSessionFeedMarkdownIsFencedCodeDelimiter(line)
        if isDelimiter {
            if isInsideFencedCodeBlock {
                isInsideFencedCodeBlock = false
                textBuffer.append(line)
            } else {
                flushTextBuffer()
                isInsideFencedCodeBlock = true
                textBuffer.append(line)
            }
            continue
        }

        if isInsideFencedCodeBlock {
            if textBuffer.isEmpty == false {
                textBuffer.append("\n")
            }
            textBuffer.append(line)
            continue
        }

        let lineSegments = structuredSessionFeedMarkdownInlineSegments(in: line)
        for segment in lineSegments {
            switch segment {
            case .text(let text):
                textBuffer.append(text)
            case .image(let ref):
                flushTextBuffer()
                segments.append(.image(ref))
            }
        }
    }

    flushTextBuffer()
    return segments
}

private func structuredSessionFeedMarkdownIsFencedCodeDelimiter(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
}

private func structuredSessionFeedMarkdownInlineSegments(
    in line: String
) -> [StructuredSessionFeedMarkdownBodySegment] {
    var segments: [StructuredSessionFeedMarkdownBodySegment] = []
    var index = line.startIndex

    while index < line.endIndex {
        guard let bang = line[index...].firstIndex(of: "!") else {
            segments.append(.text(String(line[index...])))
            break
        }

        if bang > index {
            segments.append(.text(String(line[index..<bang])))
        }

        let bracketAfterBang = line.index(after: bang)
        guard bracketAfterBang < line.endIndex, line[bracketAfterBang] == "[" else {
            segments.append(.text(String(line[bang...])))
            break
        }
        let altStart = line.index(after: bracketAfterBang)
        guard let altEnd = line[altStart...].firstIndex(of: "]"),
            line.index(after: altEnd) < line.endIndex,
            line[line.index(after: altEnd)] == "("
        else {
            segments.append(.text(String(line[altStart...])))
            break
        }

        guard line.index(altEnd, offsetBy: 2, limitedBy: line.endIndex) != nil else {
            segments.append(.text(String(line[altStart...])))
            break
        }
        let urlStart = line.index(altEnd, offsetBy: 2)
        guard let urlEnd = line[urlStart...].firstIndex(of: ")") else {
            segments.append(.text(String(line[altStart...])))
            break
        }

        let alt = String(line[altStart..<altEnd])
        let url = String(line[urlStart..<urlEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty == false {
            segments.append(.image(StructuredSessionFeedMarkdownImageReference(altText: alt, urlString: url)))
            index = line.index(after: urlEnd)
        } else {
            segments.append(.text(String(line[altStart...])))
            break
        }
    }

    return segments
}
