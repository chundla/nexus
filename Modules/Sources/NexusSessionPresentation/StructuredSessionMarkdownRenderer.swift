import Foundation
import SwiftUI

public struct StructuredSessionMarkdownRendererMetrics: Equatable, Sendable {
    public let plainTextBypassCount: Int
    public let cacheHitCount: Int
    public let cacheMissCount: Int
    public let parseCount: Int
    public let evictionCount: Int
    public let cachedEntryCount: Int

    public init(
        plainTextBypassCount: Int,
        cacheHitCount: Int,
        cacheMissCount: Int,
        parseCount: Int,
        evictionCount: Int,
        cachedEntryCount: Int
    ) {
        self.plainTextBypassCount = plainTextBypassCount
        self.cacheHitCount = cacheHitCount
        self.cacheMissCount = cacheMissCount
        self.parseCount = parseCount
        self.evictionCount = evictionCount
        self.cachedEntryCount = cachedEntryCount
    }
}

@available(macOS 12.0, iOS 15.0, *)
public final class StructuredSessionMarkdownRenderer: @unchecked Sendable {
    public static let shared = StructuredSessionMarkdownRenderer()

    private struct CacheEntry {
        var value: AttributedString
        var previousKey: String?
        var nextKey: String?
    }

    private struct Metrics {
        var plainTextBypassCount = 0
        var cacheHitCount = 0
        var cacheMissCount = 0
        var parseCount = 0
        var evictionCount = 0
    }

    private let cacheLimit: Int
    private let parser: (String) -> AttributedString
    private let lock = NSLock()

    private var cache: [String: CacheEntry] = [:]
    private var leastRecentlyUsedKey: String?
    private var mostRecentlyUsedKey: String?
    private var metrics = Metrics()

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
            lock.lock()
            metrics.plainTextBypassCount += 1
            lock.unlock()
            return AttributedString(text)
        }

        lock.lock()
        if let cached = cachedValue(for: text) {
            metrics.cacheHitCount += 1
            lock.unlock()
            return cached
        }
        metrics.cacheMissCount += 1
        lock.unlock()

        let rendered = parser(text)

        guard cacheLimit > 0 else {
            lock.lock()
            metrics.parseCount += 1
            lock.unlock()
            return rendered
        }

        lock.lock()
        if let cached = cachedValue(for: text) {
            metrics.cacheHitCount += 1
            lock.unlock()
            return cached
        }

        metrics.parseCount += 1
        insert(rendered, for: text)
        lock.unlock()

        return rendered
    }

    public func clearCache() {
        lock.lock()
        cache.removeAll(keepingCapacity: true)
        leastRecentlyUsedKey = nil
        mostRecentlyUsedKey = nil
        lock.unlock()
    }

    public func resetMetrics(clearCache: Bool = false) {
        lock.lock()
        metrics = Metrics()
        if clearCache {
            cache.removeAll(keepingCapacity: true)
            leastRecentlyUsedKey = nil
            mostRecentlyUsedKey = nil
        }
        lock.unlock()
    }

    public func metricsSnapshot() -> StructuredSessionMarkdownRendererMetrics {
        lock.lock()
        let snapshot = StructuredSessionMarkdownRendererMetrics(
            plainTextBypassCount: metrics.plainTextBypassCount,
            cacheHitCount: metrics.cacheHitCount,
            cacheMissCount: metrics.cacheMissCount,
            parseCount: metrics.parseCount,
            evictionCount: metrics.evictionCount,
            cachedEntryCount: cache.count
        )
        lock.unlock()
        return snapshot
    }

    private func cachedValue(for key: String) -> AttributedString? {
        guard let entry = cache[key] else {
            return nil
        }

        moveToMostRecentlyUsed(key)
        return entry.value
    }

    private func insert(_ value: AttributedString, for key: String) {
        if cache[key] != nil {
            cache[key]?.value = value
            moveToMostRecentlyUsed(key)
            return
        }

        let entry = CacheEntry(
            value: value,
            previousKey: mostRecentlyUsedKey,
            nextKey: nil
        )
        cache[key] = entry

        if let mostRecentlyUsedKey {
            cache[mostRecentlyUsedKey]?.nextKey = key
        }

        if leastRecentlyUsedKey == nil {
            leastRecentlyUsedKey = key
        }
        mostRecentlyUsedKey = key

        while cache.count > cacheLimit, let leastRecentlyUsedKey {
            removeValue(for: leastRecentlyUsedKey)
            metrics.evictionCount += 1
        }
    }

    private func moveToMostRecentlyUsed(_ key: String) {
        guard mostRecentlyUsedKey != key, let entry = cache[key] else {
            return
        }

        if let previousKey = entry.previousKey {
            cache[previousKey]?.nextKey = entry.nextKey
        } else {
            leastRecentlyUsedKey = entry.nextKey
        }

        if let nextKey = entry.nextKey {
            cache[nextKey]?.previousKey = entry.previousKey
        }

        var updatedEntry = entry
        updatedEntry.previousKey = mostRecentlyUsedKey
        updatedEntry.nextKey = nil
        cache[key] = updatedEntry

        if let mostRecentlyUsedKey {
            cache[mostRecentlyUsedKey]?.nextKey = key
        }
        mostRecentlyUsedKey = key

        if leastRecentlyUsedKey == nil {
            leastRecentlyUsedKey = key
        }
    }

    private func removeValue(for key: String) {
        guard let entry = cache.removeValue(forKey: key) else {
            return
        }

        if let previousKey = entry.previousKey {
            cache[previousKey]?.nextKey = entry.nextKey
        } else {
            leastRecentlyUsedKey = entry.nextKey
        }

        if let nextKey = entry.nextKey {
            cache[nextKey]?.previousKey = entry.previousKey
        } else {
            mostRecentlyUsedKey = entry.previousKey
        }
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
