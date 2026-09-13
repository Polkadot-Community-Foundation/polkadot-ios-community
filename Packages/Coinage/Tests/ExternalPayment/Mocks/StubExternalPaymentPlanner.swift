import BigInt
import Foundation
import os
import SubstrateSdk
@testable import Coinage

/// Scripted planner: answers from `handler` when set, else from a FIFO queue, else `defaultResult`.
/// Records every amount it was asked to plan. `canPayPrivately` answers `privateAnswer`.
final class StubExternalPaymentPlanner: ExternalPaymentPlanning, @unchecked Sendable {
    struct Failure: LocalizedError, Equatable {
        let message: String

        init(_ message: String = "planner boom") {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    typealias Handler = @Sendable (Balance) -> Result<ExternalPaymentPreview, Error>

    private struct State {
        var queue: [Result<ExternalPaymentPreview, Error>] = []
        var defaultResult: Result<ExternalPaymentPreview, Error>
        var calls: [Balance] = []
        var privateCalls: [Balance] = []
        var privateAnswer: Result<Bool, Error> = .success(true)
        var handler: Handler?
        var blockUntilCancelled = false
    }

    private let state: OSAllocatedUnfairLock<State>

    init(defaultResult: Result<ExternalPaymentPreview, Error> = .success(.notEnoughBalance)) {
        state = OSAllocatedUnfairLock(initialState: State(defaultResult: defaultResult))
    }

    func script(_ results: [Result<ExternalPaymentPreview, Error>]) {
        state.withLock { $0.queue.append(contentsOf: results) }
    }

    func setDefault(_ result: Result<ExternalPaymentPreview, Error>) {
        state.withLock { $0.defaultResult = result }
    }

    func setHandler(_ handler: @escaping Handler) {
        state.withLock { $0.handler = handler }
    }

    func setPrivateAnswer(_ answer: Result<Bool, Error>) {
        state.withLock { $0.privateAnswer = answer }
    }

    /// Every plan call suspends until the surrounding task is cancelled.
    func blockUntilCancelled() {
        state.withLock { $0.blockUntilCancelled = true }
    }

    var calls: [Balance] { state.withLock { $0.calls } }
    var privateCalls: [Balance] { state.withLock { $0.privateCalls } }

    func plan(amount: Balance, context _: DenominationBreakdownContext) async throws -> ExternalPaymentPreview {
        let (result, blocks) = state.withLock { state -> (Result<ExternalPaymentPreview, Error>, Bool) in
            state.calls.append(amount)
            if let handler = state.handler {
                return (handler(amount), state.blockUntilCancelled)
            }
            let next = state.queue.isEmpty ? state.defaultResult : state.queue.removeFirst()
            return (next, state.blockUntilCancelled)
        }

        if blocks {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(5))
            }
            throw CancellationError()
        }

        return try result.get()
    }

    func canPayPrivately(amount: Balance, context _: DenominationBreakdownContext) async throws -> Bool {
        try state.withLock { state in
            state.privateCalls.append(amount)
            return try state.privateAnswer.get()
        }
    }
}
