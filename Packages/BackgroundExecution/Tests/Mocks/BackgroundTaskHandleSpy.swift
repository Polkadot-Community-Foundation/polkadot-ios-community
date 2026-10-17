import os
@testable import BackgroundExecution

/// Records completions and lets a test fire the OS expiration on demand.
final class BackgroundTaskHandleSpy: BackgroundTaskHandle, @unchecked Sendable {
    private struct State {
        var expirationHandler: (@Sendable () -> Void)?
        var completions: [Bool] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let completed = AsyncStream<Bool>.makeStream()

    var expirationHandler: (@Sendable () -> Void)? {
        get { state.withLock(\.expirationHandler) }
        set { state.withLock { $0.expirationHandler = newValue } }
    }

    var completions: [Bool] {
        state.withLock(\.completions)
    }

    func setTaskCompleted(success: Bool) {
        state.withLock { $0.completions.append(success) }
        completed.continuation.yield(success)
    }

    func fireExpiration() {
        expirationHandler?()
    }

    /// Waits for the first completion; later ones stay visible through `completions`.
    func waitForCompletion() async -> Bool? {
        for await success in completed.stream {
            return success
        }
        return nil
    }
}
