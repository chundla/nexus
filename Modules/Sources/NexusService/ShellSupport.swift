#if os(macOS)
import Darwin
import Foundation

enum SupportedShellFamily {
    case posix
    case cShell
    case fish
}

enum ShellSupport {
    static let commonShellPaths = [
        "/bin/zsh",
        "/usr/bin/zsh",
        "/bin/bash",
        "/usr/bin/bash",
        "/bin/sh",
        "/usr/bin/sh",
        "/bin/ksh",
        "/usr/bin/ksh",
        "/bin/dash",
        "/usr/bin/dash",
        "/bin/csh",
        "/usr/bin/csh",
        "/bin/tcsh",
        "/usr/bin/tcsh",
        "/opt/homebrew/bin/fish",
        "/usr/local/bin/fish",
        "/usr/bin/fish",
        "/bin/fish"
    ]

    static func shellFamily(for shellPath: String) -> SupportedShellFamily {
        switch URL(fileURLWithPath: shellPath).lastPathComponent.lowercased() {
        case "csh", "tcsh":
            return .cShell
        case "fish":
            return .fish
        default:
            return .posix
        }
    }

    static func localShellCandidates(
        environment: [String: String],
        fileManager: FileManager
    ) -> [String] {
        var shells: [String] = []
        var seen: Set<String> = []

        let loginShell = getpwuid(getuid()).flatMap { entry in
            entry.pointee.pw_shell.map { String(cString: $0) }
        }

        for candidate in [environment["SHELL"], loginShell].compactMap({ $0 }) + etcShells(fileManager: fileManager) + commonShellPaths {
            guard candidate.isEmpty == false,
                  seen.insert(candidate).inserted else {
                continue
            }
            shells.append(candidate)
        }

        return shells
    }

    static func remoteShellCandidateListScript() -> String {
        (["\"${SHELL:-}\""] + commonShellPaths.map { "\"\($0)\"" } + ["$(grep '^/' /etc/shells 2>/dev/null)"])
            .joined(separator: " ")
    }

    private static func etcShells(fileManager: FileManager) -> [String] {
        let shellsPath = "/etc/shells"
        guard fileManager.isReadableFile(atPath: shellsPath),
              let contents = try? String(contentsOfFile: shellsPath, encoding: .utf8) else {
            return []
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("/") }
    }
}
#endif
