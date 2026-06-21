import Foundation

/// Estimates whether a composer draft has grown past its collapsed line limit, so a
/// disclosure control can appear only once there's actually hidden text to reveal.
/// `averageCharactersPerLine` should roughly match the composer's width/font so the
/// estimate tracks real wrapping without measuring text views directly.
enum ComposerOverflowHeuristic {
    static func exceedsCollapsedLineLimit(
        _ text: String,
        collapsedLines: Int,
        averageCharactersPerLine: Int
    ) -> Bool {
        guard text.isEmpty == false else {
            return false
        }

        var lineCount = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineCount += max(1, Int((Double(line.count) / Double(averageCharactersPerLine)).rounded(.up)))
            if lineCount > collapsedLines {
                return true
            }
        }

        return false
    }
}
