#if os(macOS)
    import Foundation

    @MainActor
    final class QuickSwitchSearchCoordinator<Result> {
        private let debounceDuration: Duration
        private let sleep: (Duration) async throws -> Void
        private var searchTask: Task<Void, Never>?
        private var searchGeneration: UInt64 = 0

        init(
            debounceDuration: Duration = .milliseconds(250),
            sleep: @escaping (Duration) async throws -> Void = { duration in
                try await Task.sleep(for: duration)
            }
        ) {
            self.debounceDuration = debounceDuration
            self.sleep = sleep
        }

        func updateQuery(
            _ rawQuery: String,
            search: @escaping (String) async throws -> Result,
            applyResults: @escaping (Result) -> Void,
            clearResults: @escaping () -> Void,
            handleError: @escaping (Error) -> Void
        ) {
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            invalidateInFlightSearch(cancellingTask: true)

            guard query.isEmpty == false else {
                clearResults()
                return
            }

            searchGeneration &+= 1
            let generation = searchGeneration

            searchTask = Task { @MainActor in
                do {
                    try await sleep(debounceDuration)
                    guard generation == searchGeneration else {
                        return
                    }
                    let results = try await search(query)
                    guard generation == searchGeneration else {
                        return
                    }
                    applyResults(results)
                } catch is CancellationError {
                } catch {
                    guard generation == searchGeneration else {
                        return
                    }
                    handleError(error)
                }

                if generation == searchGeneration {
                    searchTask = nil
                }
            }
        }

        func cancel() {
            invalidateInFlightSearch(cancellingTask: true)
        }

        private func invalidateInFlightSearch(cancellingTask: Bool) {
            if cancellingTask {
                searchTask?.cancel()
                searchTask = nil
            }
            searchGeneration &+= 1
        }
    }
#endif
