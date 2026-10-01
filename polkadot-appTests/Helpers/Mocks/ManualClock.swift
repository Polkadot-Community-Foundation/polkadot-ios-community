import Foundation
import os
import Testing

/// A clock whose sleeps finish only when the test resumes them, addressed by requested duration.
/// Unlike `TestClock`, nothing here depends on a sleep being registered before time moves: the test
/// waits for the registration itself. `now` never moves, so a deadline equals its requested duration
/// and code measuring elapsed time through `now` always sees zero.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    fileprivate struct Sleeper {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    fileprivate struct Waiter {
        let duration: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    fileprivate struct State {
        var sleepers: [Sleeper] = []
        var waiters: [Waiter] = []
        var cancelledIds: Set<UUID> = []
    }

    let now = Instant(offset: .zero)
    let minimumResolution: Duration = .zero

    private let state = OSAllocatedUnfairLock(initialState: State())

    func sleep(until deadline: Instant, tolerance _: Duration? = nil) async throws {
        let id = UUID()
        let duration = now.duration(to: deadline)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(Sleeper(id: id, duration: duration, continuation: continuation))
            }
        } onCancel: {
            cancel(id: id)
        }
    }

    /// Suspends until a sleep of `duration` is pending, without finishing it.
    func waitForSleep(for duration: Duration) async {
        await withCheckedContinuation { continuation in
            let isPending = state.withLock { state in
                guard !state.sleepers.contains(where: { $0.duration == duration }) else { return true }

                state.waiters.append(Waiter(duration: duration, continuation: continuation))

                return false
            }

            if isPending {
                continuation.resume()
            }
        }
    }

    /// Waits for a sleep of `duration` to be pending, then finishes it.
    func resumeSleep(
        for duration: Duration,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await waitForSleep(for: duration)

        let sleeper: Sleeper? = state.withLock { state in
            guard let index = state.sleepers.firstIndex(where: { $0.duration == duration }) else { return nil }

            return state.sleepers.remove(at: index)
        }

        guard let sleeper else {
            Issue.record(
                "The \(duration) sleep was cancelled before it could be resumed",
                sourceLocation: sourceLocation
            )
            return
        }

        sleeper.continuation.resume()
    }
}

private extension ManualClock {
    func register(_ sleeper: Sleeper) {
        let (isCancelled, readyWaiters): (Bool, [Waiter]) = state.withLock { state in
            guard state.cancelledIds.remove(sleeper.id) == nil else { return (true, []) }

            state.sleepers.append(sleeper)

            let ready = state.waiters.filter { $0.duration == sleeper.duration }
            state.waiters.removeAll { $0.duration == sleeper.duration }

            return (false, ready)
        }

        if isCancelled {
            sleeper.continuation.resume(throwing: CancellationError())
        }

        readyWaiters.forEach { $0.continuation.resume() }
    }

    /// Cancellation can arrive before registration, so an unknown id is remembered for `register`.
    func cancel(id: UUID) {
        let sleeper: Sleeper? = state.withLock { state in
            guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                state.cancelledIds.insert(id)
                return nil
            }

            return state.sleepers.remove(at: index)
        }

        sleeper?.continuation.resume(throwing: CancellationError())
    }
}
