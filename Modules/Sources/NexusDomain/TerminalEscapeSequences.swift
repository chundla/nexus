import Foundation

/// Strips terminal control sequences from provider text destined for SwiftUI plain `Text`, not styled terminal views.
public enum TerminalEscapeSequences {
    public static func stripForPlainDisplay(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0 == "\u{001B}" || $0 == "\u{009B}" }) else {
            return text
        }

        var result = ""
        var iterator = text.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            switch scalar {
            case "\u{001B}":
                guard let next = iterator.next() else {
                    break
                }
                switch next {
                case "[":
                    skipCSI(iterator: &iterator)
                case "]":
                    skipStringCommand(iterator: &iterator, allowBellTerminator: true)
                case "P", "X", "^", "_":
                    skipStringCommand(iterator: &iterator, allowBellTerminator: false)
                case "(", ")":
                    _ = iterator.next()
                default:
                    break
                }
            case "\u{009B}":
                skipCSI(iterator: &iterator)
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return String(result)
    }

    private static func skipCSI(iterator: inout String.UnicodeScalarView.Iterator) {
        while let scalar = iterator.next() {
            if (0x40...0x7E).contains(scalar.value) {
                return
            }
        }
    }

    private static func skipStringCommand(
        iterator: inout String.UnicodeScalarView.Iterator,
        allowBellTerminator: Bool
    ) {
        while let scalar = iterator.next() {
            if allowBellTerminator, scalar == "\u{0007}" {
                return
            }
            if scalar == "\u{001B}", let terminator = iterator.next(), terminator == "\\" {
                return
            }
        }
    }
}