#if os(macOS)
    import Foundation

    protocol LocalShellEnvironmentResolving: Sendable {
        func resolvedEnvironment() -> [String: String]?
    }

    /// `resolvedEnvironment()` spawns an interactive login shell (`-lic`) to capture
    /// shell-managed PATH/env state (nvm, pyenv, etc.). That spawn alone costs multiple
    /// seconds on common shell setups, so repeat calls within `ttl` reuse the last result
    /// instead of paying the interactive-shell tax on every Session launch.
    final class ResolvedEnvironmentCache: @unchecked Sendable {
        private let lock = NSLock()
        private let ttl: TimeInterval
        private let currentDate: () -> Date
        private var cachedEnvironment: [String: String]?
        private var resolvedAt: Date?

        init(ttl: TimeInterval = 300, currentDate: @escaping () -> Date = Date.init) {
            self.ttl = ttl
            self.currentDate = currentDate
        }

        func value(resolve: () -> [String: String]?) -> [String: String]? {
            lock.lock()
            if let cachedEnvironment, let resolvedAt, currentDate().timeIntervalSince(resolvedAt) <= ttl {
                lock.unlock()
                return cachedEnvironment
            }
            lock.unlock()

            let resolved = resolve()

            lock.lock()
            if let resolved {
                cachedEnvironment = resolved
                resolvedAt = currentDate()
            }
            lock.unlock()

            return resolved
        }
    }

    struct LocalShellEnvironmentResolver: LocalShellEnvironmentResolving {
        private let baseEnvironment: [String: String]
        private let commandRunner: any ProviderCommandRunning
        private let localShellCommandBuilder: LocalShellCommandBuilder
        private let cache: ResolvedEnvironmentCache

        init(
            baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
            commandRunner: any ProviderCommandRunning = SystemProviderCommandRunner(),
            localShellCommandBuilder: LocalShellCommandBuilder = LocalShellCommandBuilder(),
            cache: ResolvedEnvironmentCache = ResolvedEnvironmentCache()
        ) {
            self.baseEnvironment = baseEnvironment
            self.commandRunner = commandRunner
            self.localShellCommandBuilder = localShellCommandBuilder
            self.cache = cache
        }

        func resolvedEnvironment() -> [String: String]? {
            cache.value { resolveUncached() }
        }

        private func resolveUncached() -> [String: String]? {
            guard let shellEnvironment = resolveViaLocalShell(), shellEnvironment.isEmpty == false else {
                return nil
            }

            return baseEnvironment.merging(shellEnvironment) { _, shellValue in
                shellValue
            }
        }

        private func resolveViaLocalShell() -> [String: String]? {
            for command in localShellCommandBuilder.candidateCommands(for: "/usr/bin/env -0") {
                do {
                    let result = try commandRunner.run(
                        executable: command.executable,
                        arguments: command.arguments,
                        currentDirectoryURL: nil
                    )
                    guard result.exitStatus == 0 else {
                        continue
                    }

                    let environment = parseEnvironment(from: result.stdout)
                    if environment.isEmpty == false {
                        return environment
                    }
                } catch {
                    continue
                }
            }

            return nil
        }

        private func parseEnvironment(from stdout: String) -> [String: String] {
            stdout
                .split(separator: "\0", omittingEmptySubsequences: true)
                .reduce(into: [String: String]()) { environment, entry in
                    let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard let key = parts.first, key.isEmpty == false else {
                        return
                    }

                    let value = parts.count == 2 ? String(parts[1]) : ""
                    environment[String(key)] = value
                }
        }
    }
#endif
