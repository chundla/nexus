import Foundation

@MainActor
final class TerminalViewportResizeCoordinator {
    struct Size: Equatable, Sendable {
        let columns: Int
        let rows: Int
    }

    typealias CurrentSizeProvider = @MainActor @Sendable () -> Size?
    typealias SubmitAction = @MainActor @Sendable (Size) async throws -> Void
    typealias ErrorHandler = @MainActor @Sendable (Error) -> Void
    typealias SleepAction = @Sendable (Duration) async -> Void

    private let delay: Duration
    private let sleep: SleepAction

    private var pendingSize: Size?
    private var lastRequestedSize: Size?
    private var processingTask: Task<Void, Never>?
    private var currentSizeProvider: CurrentSizeProvider?
    private var submitAction: SubmitAction?
    private var errorHandler: ErrorHandler?

    init(
        delay: Duration = .milliseconds(100),
        sleep: @escaping SleepAction = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    deinit {
        processingTask?.cancel()
    }

    func report(
        _ size: Size,
        currentSize: @escaping CurrentSizeProvider,
        submit: @escaping SubmitAction,
        onError: @escaping ErrorHandler
    ) {
        syncLastRequestedSize(currentSize: currentSize)

        guard size.columns > 0, size.rows > 0 else {
            return
        }
        guard currentSize() != size,
            pendingSize != size,
            lastRequestedSize != size
        else {
            return
        }

        currentSizeProvider = currentSize
        submitAction = submit
        errorHandler = onError
        pendingSize = size

        guard processingTask == nil else {
            return
        }

        processingTask = Task { @MainActor [weak self] in
            await self?.processPendingSizes()
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        pendingSize = nil
        lastRequestedSize = nil
    }

    private func processPendingSizes() async {
        defer { processingTask = nil }

        while true {
            guard pendingSize != nil,
                let currentSizeProvider,
                let submitAction,
                let errorHandler
            else {
                return
            }

            await sleep(delay)
            guard Task.isCancelled == false else {
                return
            }
            guard let targetSize = pendingSize else {
                continue
            }

            pendingSize = nil
            syncLastRequestedSize(currentSize: currentSizeProvider)

            guard currentSizeProvider() != targetSize,
                lastRequestedSize != targetSize
            else {
                continue
            }

            lastRequestedSize = targetSize

            do {
                try await submitAction(targetSize)
            } catch {
                if lastRequestedSize == targetSize {
                    lastRequestedSize = nil
                }
                errorHandler(error)
            }
        }
    }

    private func syncLastRequestedSize(currentSize: CurrentSizeProvider) {
        guard let lastRequestedSize,
            currentSize() != lastRequestedSize
        else {
            return
        }

        self.lastRequestedSize = nil
    }
}
