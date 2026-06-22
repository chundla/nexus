#if os(macOS)
    import Foundation

    protocol LocalShellEnvironmentResolving: Sendable {
        func resolvedEnvironment() -> [String: String]?
    }

    protocol LocalShellEnvironmentPersisting: Sendable {
        func loadCachedLocalShellEnvironment() -> [String: String]?
        func saveCachedLocalShellEnvironment(_ environment: [String: String])
    }

    /// `resolvedEnvironment()` spawns an interactive login shell (`zsh -lic`) to capture
    /// nvm/pyenv-managed PATH and env state. That spawn alone costs multiple seconds on
    /// common shell setups (shell integration, version managers, prompt themes). A user's
    /// login shell environment essentially never changes while the service is running, so
    /// this cache is a blanket, indefinite cache rather than a short TTL: resolve once,
    /// reuse forever, and only pay the shell-spawn cost again via an explicit `refresh()`
    /// (driven by service startup prewarm), never synchronously on a Session launch.
    final class ResolvedEnvironmentCache: @unchecked Sendable {
        private let lock = NSLock()
        private let persistence: (any LocalShellEnvironmentPersisting)?
        private var cachedEnvironment: [String: String]?
        private var hasLoadedFromPersistence = false

        init(persistence: (any LocalShellEnvironmentPersisting)? = nil) {
            self.persistence = persistence
        }

        func value(resolve: () -> [String: String]?) -> [String: String]? {
            lock.lock()
            if hasLoadedFromPersistence == false {
                hasLoadedFromPersistence = true
                cachedEnvironment = persistence?.loadCachedLocalShellEnvironment()
            }
            if let cachedEnvironment {
                lock.unlock()
                return cachedEnvironment
            }
            lock.unlock()

            let resolved = resolve()
            store(resolved)
            return resolved
        }

        @discardableResult
        func refresh(resolve: () -> [String: String]?) -> [String: String]? {
            let resolved = resolve()
            store(resolved)
            return resolved
        }

        private func store(_ resolved: [String: String]?) {
            guard let resolved else {
                return
            }

            lock.lock()
            cachedEnvironment = resolved
            hasLoadedFromPersistence = true
            lock.unlock()

            persistence?.saveCachedLocalShellEnvironment(resolved)
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

        @discardableResult
        func refreshResolvedEnvironment() -> [String: String]? {
            cache.refresh { resolveUncached() }
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
