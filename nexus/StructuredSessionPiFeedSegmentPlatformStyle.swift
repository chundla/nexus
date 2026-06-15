import NexusSessionPresentation
import SwiftUI

#if os(macOS)
    import AppKit

    func macOSPiStructuredSessionFeedSegmentStyle() -> StructuredSessionPiFeedSegmentStyle {
        StructuredSessionPiFeedSegmentStyle(
            userBubbleBackground: NexusMacTheme.gold,
            userBubbleForeground: .white,
            assistantBubbleBackground: Color.white.opacity(0.1),
            assistantLabelForeground: NexusMacTheme.mutedText,
            assistantBodyForeground: .white.opacity(0.94),
            toolAccent: NexusMacTheme.teal,
            mutedForeground: NexusMacTheme.mutedText,
            systemCapsuleBackground: Color.white.opacity(0.05),
            bodyFont: { size, style, weight in
                let base = NexusMacTheme.bodyFont(size, relativeTo: style ?? .body)
                if let weight, weight != .regular {
                    return base.weight(weight)
                }
                return base
            },
            monoFont: { size, style in
                NexusMacTheme.monoFont(size, relativeTo: style ?? .body)
            },
            charactersPerLine: 72
        )
    }
#endif

#if os(iOS)
    func iosPiStructuredSessionFeedSegmentStyle(feedReaderIsScrollIdle: Bool) -> StructuredSessionPiFeedSegmentStyle {
        StructuredSessionPiFeedSegmentStyle(
            userBubbleBackground: NexusIOSTheme.gold,
            userBubbleForeground: .white,
            assistantBubbleBackground: Color.white.opacity(0.1),
            assistantLabelForeground: NexusIOSTheme.mutedText,
            assistantBodyForeground: .white.opacity(0.94),
            toolAccent: NexusIOSTheme.gold,
            mutedForeground: NexusIOSTheme.mutedText,
            systemCapsuleBackground: Color.white.opacity(0.05),
            bodyFont: { size, style, weight in
                NexusIOSTheme.bodyFont(size, relativeTo: style ?? .body, weight: weight ?? .regular)
            },
            monoFont: { size, style in
                NexusIOSTheme.monoFont(size, relativeTo: style ?? .body)
            },
            charactersPerLine: 56,
            feedReaderIsScrollIdle: feedReaderIsScrollIdle
        )
    }
#endif
