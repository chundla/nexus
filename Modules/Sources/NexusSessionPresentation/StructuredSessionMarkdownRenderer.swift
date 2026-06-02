import Foundation
import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
public final class StructuredSessionMarkdownRenderer: @unchecked Sendable {
    public static let shared = StructuredSessionMarkdownRenderer()

    private let cacheLimit: Int
    private let parser: (String) -> AttributedString
    private let lock = NSLock()
    private var cache: [String: AttributedString] = [:]
    private var cacheOrder: [String] = []

    public init(cacheLimit: Int = 256) {
        self.cacheLimit = cacheLimit
        self.parser = Self.defaultParse
    }

    init(
        cacheLimit: Int = 256,
        parser: @escaping (String) -> AttributedString
    ) {
        self.cacheLimit = cacheLimit
        self.parser = parser
    }

    public func render(_ text: String) -> AttributedString {
        guard Self.requiresMarkdownParsing(text) else {
            return AttributedString(text)
        }

        lock.lock()
        if let cached = cache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let rendered = parser(text)

        guard cacheLimit > 0 else {
            return rendered
        }

        lock.lock()
        if let cached = cache[text] {
            lock.unlock()
            return cached
        }

        cache[text] = rendered
        cacheOrder.append(text)
        while cacheOrder.count > cacheLimit {
            let evictedKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: evictedKey)
        }
        lock.unlock()

        return rendered
    }

    static func requiresMarkdownParsing(_ text: String) -> Bool {
        guard text.isEmpty == false else {
            return false
        }

        if text.contains("```") {
            return true
        }

        if text.contains("\n") {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") ||
                    trimmed.hasPrefix(">") ||
                    trimmed.hasPrefix("- ") ||
                    trimmed.hasPrefix("* ") ||
                    trimmed.hasPrefix("+ ") ||
                    trimmed.hasPrefix("1. ") {
                    return true
                }
            }
        }

        return text.contains("`") ||
            text.contains("*") ||
            text.contains("_") ||
            text.contains("[") ||
            text.contains("!") ||
            text.contains("~")
    }

    private static func defaultParse(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionMarkdownText: View {
    private let markdown: String
    private let font: Font
    private let color: Color
    private let renderer: StructuredSessionMarkdownRenderer

    @State private var attributed: AttributedString

    public init(
        markdown: String,
        font: Font,
        color: Color,
        renderer: StructuredSessionMarkdownRenderer = .shared
    ) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.renderer = renderer
        _attributed = State(initialValue: renderer.render(markdown))
    }

    public var body: some View {
        Text(attributed)
            .font(font)
            .foregroundColor(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: markdown) { newValue in
                attributed = renderer.render(newValue)
            }
    }
}
