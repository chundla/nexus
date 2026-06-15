import Foundation
import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
public enum StructuredSessionRenderedText: Equatable, Sendable {
    case plain(String)
    case attributed(AttributedString)
    case segments([StructuredSessionFeedMarkdownSegment])
}

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
        switch renderContent(text) {
        case .plain(let text):
            return AttributedString(text)
        case .attributed(let attributed):
            return attributed
        case .segments(let segments):
            return Self.attributedString(fromFeedSegments: segments, proseRenderer: parser)
        }
    }

    private static func attributedString(
        fromFeedSegments segments: [StructuredSessionFeedMarkdownSegment],
        proseRenderer: (String) -> AttributedString
    ) -> AttributedString {
        var rendered = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                rendered.append(AttributedString("\n\n"))
            }
            switch segment {
            case .prose(let prose):
                rendered.append(proseRenderer(prose))
            case .fencedCode(_, let content):
                rendered.append(AttributedString(content))
            }
        }
        return rendered
    }

    public func renderContent(_ text: String) -> StructuredSessionRenderedText {
        if structuredSessionFeedDisplayMathUsesPlainFallback(for: text) {
            lock.lock()
            metrics.plainTextBypassCount += 1
            lock.unlock()
            return .plain(text)
        }

        guard Self.requiresMarkdownParsing(text) else {
            lock.lock()
            metrics.plainTextBypassCount += 1
            lock.unlock()
            return .plain(text)
        }

        if text.contains("```") {
            lock.lock()
            metrics.cacheMissCount += 1
            metrics.parseCount += 1
            lock.unlock()
            return .segments(structuredSessionFeedMarkdownParse(text).segments)
        }

        lock.lock()
        if let cached = cachedValue(for: text) {
            metrics.cacheHitCount += 1
            lock.unlock()
            return .attributed(cached)
        }
        metrics.cacheMissCount += 1
        lock.unlock()

        let rendered = parser(text)

        guard cacheLimit > 0 else {
            lock.lock()
            metrics.parseCount += 1
            lock.unlock()
            return .attributed(rendered)
        }

        lock.lock()
        if let cached = cachedValue(for: text) {
            metrics.cacheHitCount += 1
            lock.unlock()
            return .attributed(cached)
        }

        metrics.parseCount += 1
        insert(rendered, for: text)
        lock.unlock()

        return .attributed(rendered)
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
                if structuredSessionFeedMarkdownLineLooksLikeTableRow(trimmed) ||
                    structuredSessionFeedMarkdownLineLooksLikeThematicBreak(trimmed) {
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
        renderFullMarkdownDocument(text)
    }

    private static func renderFullMarkdownDocument(_ text: String) -> AttributedString {
        if #available(macOS 13.0, iOS 16.0, *) {
            if let rendered = try? AttributedString(
                markdown: text,
                options: .init(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                return rendered
            }
        }

        return renderInlineOnlyMarkdownPreservingLineBreaks(text)
    }

    /// Fallback when full document parsing is unavailable or fails.
    private static func renderInlineOnlyMarkdownPreservingLineBreaks(_ text: String) -> AttributedString {
        var rendered = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for index in lines.indices {
            let line = String(lines[index])
            rendered.append(renderInlineMarkdown(line))
            if index < lines.index(before: lines.endIndex) {
                rendered.append(AttributedString("\n"))
            }
        }

        return rendered
    }

    private static func renderInlineMarkdown(_ line: String) -> AttributedString {
        guard requiresInlineMarkdownParsing(line) else {
            return AttributedString(line)
        }

        return (try? AttributedString(
            markdown: line,
            options: inlineMarkdownParsingOptions()
        )) ?? AttributedString(line)
    }

    private static func requiresInlineMarkdownParsing(_ text: String) -> Bool {
        text.contains("`") ||
            text.contains("*") ||
            text.contains("_") ||
            text.contains("[") ||
            text.contains("!") ||
            text.contains("~")
    }

    static func structuredSessionFeedMarkdownLineLooksLikeTableRow(_ trimmedLine: String) -> Bool {
        guard trimmedLine.contains("|") else {
            return false
        }
        let pipeCount = trimmedLine.filter { $0 == "|" }.count
        return pipeCount >= 2
    }

    static func structuredSessionFeedMarkdownLineLooksLikeThematicBreak(_ trimmedLine: String) -> Bool {
        guard trimmedLine.isEmpty == false else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "-_* ")
        return trimmedLine.unicodeScalars.allSatisfy { allowed.contains($0) }
            && trimmedLine.contains(where: { $0 == "-" || $0 == "*" || $0 == "_" })
            && trimmedLine.filter { $0 != " " }.count >= 3
    }

    private static func inlineMarkdownParsingOptions() -> AttributedString.MarkdownParsingOptions {
        if #available(macOS 13.0, iOS 16.0, *) {
            return .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        }

        return .init(
            interpretedSyntax: .inlineOnly,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
    }

}

/// Parses deferred row markdown off the main thread, then delivers on the main actor (#225).
@available(macOS 12.0, iOS 15.0, *)
public enum StructuredSessionMarkdownRowHydrationScheduler {
    private struct RenderedDelivery: Sendable {
        let rendered: StructuredSessionRenderedText
        let deliver: @Sendable @MainActor (StructuredSessionRenderedText) -> Void
    }

    private actor Queue {
        struct Job {
            let markdown: String
            let renderer: StructuredSessionMarkdownRenderer
            let deliver: @Sendable @MainActor (StructuredSessionRenderedText) -> Void
        }

        var pendingJobs: [Job] = []
        var isDraining = false

        func enqueue(_ job: Job) -> Bool {
            pendingJobs.append(job)
            guard isDraining == false else {
                return false
            }
            isDraining = true
            return true
        }

        func dequeueUpTo(_ limit: Int) -> [Job] {
            guard limit > 0, pendingJobs.isEmpty == false else {
                return []
            }
            let count = min(limit, pendingJobs.count)
            let batch = Array(pendingJobs.prefix(count))
            pendingJobs.removeFirst(count)
            return batch
        }

        func markIdleIfEmpty() -> Bool {
            guard pendingJobs.isEmpty else {
                return false
            }
            isDraining = false
            return true
        }

        var deliveryFlushCountForTesting = 0

        func recordDeliveryFlushForTesting() {
            deliveryFlushCountForTesting += 1
        }

        func deliveryFlushCountForTestingSnapshot() -> Int {
            deliveryFlushCountForTesting
        }

        func resetDeliveryFlushCountForTesting() {
            deliveryFlushCountForTesting = 0
        }

        func hasPendingOrDraining() -> Bool {
            isDraining || pendingJobs.isEmpty == false
        }

        func waitUntilIdle() async {
            while isDraining || pendingJobs.isEmpty == false {
                await Task.yield()
            }
        }
    }

    private static let queue = Queue()

    /// Limits SwiftUI row state updates per main-actor turn during feed paint/finalization (#225).
    private static var maxDeliveriesPerMainActorFlush: Int {
        #if os(iOS)
        1
        #else
        2
        #endif
    }

    public static func scheduleHydration(
        markdown: String,
        renderer: StructuredSessionMarkdownRenderer,
        deliver: @escaping @MainActor (StructuredSessionRenderedText) -> Void
    ) {
        let job = Queue.Job(markdown: markdown, renderer: renderer, deliver: deliver)
        Task.detached(priority: .utility) {
            let shouldStartDrain = await queue.enqueue(job)
            guard shouldStartDrain else {
                return
            }
            await drainUntilIdle()
        }
    }

    private static func drainUntilIdle() async {
        while true {
            let batch = await queue.dequeueUpTo(maxDeliveriesPerMainActorFlush)
            guard batch.isEmpty == false else {
                _ = await queue.markIdleIfEmpty()
                return
            }

            var deliveries: [RenderedDelivery] = []
            deliveries.reserveCapacity(batch.count)
            for job in batch {
                let rendered = job.renderer.renderContent(job.markdown)
                deliveries.append(RenderedDelivery(rendered: rendered, deliver: job.deliver))
            }

            await MainActor.run {
                for delivery in deliveries {
                    delivery.deliver(delivery.rendered)
                }
            }
            await queue.recordDeliveryFlushForTesting()
            await Task.yield()
        }
    }

    /// Waits until scheduled hydration work finishes; for tests only.
    public static func drainForTesting() async {
        for _ in 0 ..< 512 {
            if await queue.hasPendingOrDraining() {
                break
            }
            await Task.yield()
        }
        await queue.waitUntilIdle()
    }

    /// Number of batched main-actor delivery flushes since last reset; for tests only.
    public static func deliveryFlushCountForTesting() async -> Int {
        await queue.deliveryFlushCountForTestingSnapshot()
    }

    public static func resetDeliveryFlushCountForTesting() async {
        await queue.resetDeliveryFlushCountForTesting()
    }
}

/// Structured feed markdown: avoid synchronous parse during first row layout, especially on startup/finalization (#225).
public enum StructuredSessionMarkdownTextInitialRenderPolicy {
    public static var defersMarkdownParseUntilFirstAppear: Bool {
        true
    }

    /// Lets the first plain-text row layout finish before hydration schedules markdown parse work (#225).
    public static var defersMarkdownHydrationUntilAfterFirstLayoutTurn: Bool {
        true
    }
}

#if os(macOS)
/// When false, `StructuredSessionMarkdownText` keeps plain text and skips row hydration (#225 startup).
private struct StructuredSessionFeedMarkdownHydrationAllowedKey: EnvironmentKey {
    static let defaultValue = true
}

@available(macOS 12.0, *)
public extension EnvironmentValues {
    var structuredSessionFeedMarkdownHydrationAllowed: Bool {
        get { self[StructuredSessionFeedMarkdownHydrationAllowedKey.self] }
        set { self[StructuredSessionFeedMarkdownHydrationAllowedKey.self] = newValue }
    }
}
#endif

@available(macOS 12.0, iOS 15.0, *)
func structuredSessionMarkdownDisplayedContent(
    markdown: String,
    renderer: StructuredSessionMarkdownRenderer,
    defersParseUntilAppear: Bool,
    hasAppeared: Bool
) -> StructuredSessionRenderedText {
    if defersParseUntilAppear,
       hasAppeared == false,
       StructuredSessionMarkdownRenderer.requiresMarkdownParsing(markdown) {
        return .plain(markdown)
    }
    return renderer.renderContent(markdown)
}

enum StructuredSessionFeedTextSelectionPolicy {
    /// Feed text selection is disabled on all platforms during scroll/stream.
    /// macOS: selection overlays can thrash layout on large multiline rows.
    /// iOS: Instruments hitch (~109 offscreen passes) correlated with per-line
    /// selection overlay work across many visible activity rows.
    static var isEnabled: Bool {
        false
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension View {
    @ViewBuilder
    func structuredSessionFeedTextSelection() -> some View {
        if StructuredSessionFeedTextSelectionPolicy.isEnabled {
            textSelection(.enabled)
        } else {
            textSelection(.disabled)
        }
    }

    /// Flatten per-row bubble chrome into one layer so scrolling does not
    /// re-rasterize every nested shape independently (iOS GPU offscreen passes).
    @ViewBuilder
    func structuredSessionFeedRowCompositing() -> some View {
        #if os(iOS)
        compositingGroup()
        #else
        self
        #endif
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionIdleGatedAssistantFeedMarkdownText: View {
    private let markdown: String
    private let font: Font
    private let color: Color
    private let prefersPlainTextUntilIdle: Bool
    private let allowsInlineMarkdownHydration: Bool
    private let renderer: StructuredSessionMarkdownRenderer

    public init(
        markdown: String,
        font: Font,
        color: Color,
        prefersPlainTextUntilIdle: Bool,
        allowsInlineMarkdownHydration: Bool,
        renderer: StructuredSessionMarkdownRenderer = .shared
    ) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.prefersPlainTextUntilIdle = prefersPlainTextUntilIdle
        self.allowsInlineMarkdownHydration = allowsInlineMarkdownHydration
        self.renderer = renderer
    }

    public var body: some View {
        Group {
            if prefersPlainTextUntilIdle,
               allowsInlineMarkdownHydration == false {
                Text(verbatim: markdown)
                    .font(font)
                    .foregroundColor(color)
                    .structuredSessionFeedTextSelection()
            } else {
                StructuredSessionMarkdownText(
                    markdown: markdown,
                    font: font,
                    color: color,
                    renderer: renderer
                )
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct StructuredSessionMarkdownText: View {
    private let markdown: String
    private let font: Font
    private let color: Color
    private let renderer: StructuredSessionMarkdownRenderer
    private let fixedVerticalSize: Bool
    private let defersInitialMarkdownParse: Bool

    @State private var hasAppeared = false
    @State private var renderedContent: StructuredSessionRenderedText
    #if os(macOS)
    @Environment(\.structuredSessionFeedMarkdownHydrationAllowed) private var feedMarkdownHydrationAllowed
    #endif

    public init(
        markdown: String,
        font: Font,
        color: Color,
        renderer: StructuredSessionMarkdownRenderer = .shared,
        fixedVerticalSize: Bool = false,
        defersInitialMarkdownParse: Bool = StructuredSessionMarkdownTextInitialRenderPolicy.defersMarkdownParseUntilFirstAppear
    ) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.renderer = renderer
        self.fixedVerticalSize = fixedVerticalSize
        self.defersInitialMarkdownParse = defersInitialMarkdownParse
        _renderedContent = State(
            initialValue: structuredSessionMarkdownDisplayedContent(
                markdown: markdown,
                renderer: renderer,
                defersParseUntilAppear: defersInitialMarkdownParse,
                hasAppeared: false
            )
        )
    }

    @MainActor
    public var body: some View {
        Group {
            switch renderedContent {
            case .plain(let text):
                Text(verbatim: text)
            case .attributed(let attributed):
                Text(attributed)
            case .segments(let segments):
                structuredSessionMarkdownSegmentStack(
                    segments: segments,
                    font: font,
                    color: color,
                    renderer: renderer
                )
            }
        }
        .font(font)
        .foregroundColor(color)
        .structuredSessionFeedTextSelection()
        .modifier(StructuredSessionMarkdownVerticalSizingModifier(fixedVerticalSize: fixedVerticalSize))
        .onAppear {
            guard hasAppeared == false else { return }
            hasAppeared = true
            guard defersInitialMarkdownParse,
                  StructuredSessionMarkdownRenderer.requiresMarkdownParsing(markdown) else {
                let next = structuredSessionMarkdownDisplayedContent(
                    markdown: markdown,
                    renderer: renderer,
                    defersParseUntilAppear: false,
                    hasAppeared: true
                )
                guard next != renderedContent else { return }
                renderedContent = next
                return
            }
            #if os(macOS)
            guard feedMarkdownHydrationAllowed else { return }
            #endif
            structuredSessionMarkdownTextScheduleRowHydration()
        }
        #if os(macOS)
        .onChange(of: feedMarkdownHydrationAllowed) { allowed in
            guard allowed, hasAppeared else { return }
            structuredSessionMarkdownTextScheduleRowHydration()
        }
        #endif
        .onChange(of: markdown) { newValue in
            let next = structuredSessionMarkdownDisplayedContent(
                markdown: newValue,
                renderer: renderer,
                defersParseUntilAppear: defersInitialMarkdownParse,
                hasAppeared: hasAppeared
            )
            guard next != renderedContent else { return }
            renderedContent = next
        }
    }

    private func structuredSessionMarkdownTextScheduleRowHydration() {
        guard defersInitialMarkdownParse,
              StructuredSessionMarkdownRenderer.requiresMarkdownParsing(markdown) else {
            return
        }
        let scheduleHydration = {
            StructuredSessionMarkdownRowHydrationScheduler.scheduleHydration(
                markdown: markdown,
                renderer: renderer
            ) { next in
                guard next != renderedContent else { return }
                renderedContent = next
            }
        }
        if StructuredSessionMarkdownTextInitialRenderPolicy.defersMarkdownHydrationUntilAfterFirstLayoutTurn {
            Task { @MainActor in
                await Task.yield()
                scheduleHydration()
            }
        } else {
            scheduleHydration()
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
@MainActor
@ViewBuilder
func structuredSessionMarkdownSegmentStack(
    segments: [StructuredSessionFeedMarkdownSegment],
    font: Font,
    color: Color,
    renderer: StructuredSessionMarkdownRenderer
) -> some View {
    let fencedPolicy = structuredSessionFeedFencedCodeBlockPolicy()
    let monoFont = font.monospaced()
    VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            switch segment {
            case .prose(let prose):
                StructuredSessionFeedRichMarkdownView(
                    markdown: prose,
                    font: font,
                    color: color
                )
            case .fencedCode(let language, let content):
                StructuredSessionFeedFencedCodeBlockView(
                    language: language,
                    content: content,
                    policy: fencedPolicy,
                    monoFont: monoFont,
                    foreground: color
                )
            }
        }
    }
}

private struct StructuredSessionMarkdownVerticalSizingModifier: ViewModifier {
    let fixedVerticalSize: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if fixedVerticalSize {
            content.fixedSize(horizontal: false, vertical: true)
        } else {
            content
        }
    }
}
