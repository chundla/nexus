#if os(macOS)
    import Foundation

    struct AsyncOperationSupport {
        static func blocking<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
            let result = LockedAsyncOperationResult<T>()
            let finished = DispatchSemaphore(value: 0)

            // Park semaphore.wait on a dedicated pthread so Swift Testing cooperative threads are
            // not held while nested Task { await ... } needs the same executor.
            let waiter = Thread {
                let group = DispatchGroup()
                group.enter()
                Task {
                    defer { group.leave() }
                    do {
                        result.store(.success(try await operation()))
                    } catch {
                        result.store(.failure(error))
                    }
                }
                group.wait()
                finished.signal()
            }
            waiter.start()
            finished.wait()
            return try result.value().get()
        }
    }

    final class AsyncResultWaiter<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var result: Result<T, Error>?

        func wait(
            timeoutNanoseconds: UInt64,
            timeoutError: @escaping @Sendable () -> Error
        ) async throws -> T {
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.fail(timeoutError())
            }
            defer { timeoutTask.cancel() }

            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        }

        func succeed(_ value: T) {
            resolve(.success(value))
        }

        func fail(_ error: Error) {
            resolve(.failure(error))
        }

        private func resolve(_ result: Result<T, Error>) {
            let continuationToResume: CheckedContinuation<T, Error>?

            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }

            if let existingContinuation = continuation {
                self.continuation = nil
                continuationToResume = existingContinuation
            } else {
                self.result = result
                continuationToResume = nil
            }
            lock.unlock()

            guard let continuationToResume else {
                return
            }

            switch result {
            case .success(let value):
                continuationToResume.resume(returning: value)
            case .failure(let error):
                continuationToResume.resume(throwing: error)
            }
        }
    }

    extension AsyncResultWaiter where T == Void {
        func succeed() {
            succeed(())
        }
    }

    private final class LockedAsyncOperationResult<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<T, Error>?

        func store(_ result: Result<T, Error>) {
            lock.lock()
            self.result = result
            lock.unlock()
        }

        func value() -> Result<T, Error> {
            lock.lock()
            defer { lock.unlock() }
            return result
                ?? .failure(
                    NSError(
                        domain: "AsyncOperationSupport", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Async operation did not complete."]))
        }
    }
#endif
