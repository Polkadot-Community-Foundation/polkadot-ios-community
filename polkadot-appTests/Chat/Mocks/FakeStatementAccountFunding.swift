import Foundation
import Individuality
import os
import SubstrateSdk

/// Records funding calls; `holdNext()` keeps the next call pending until `release()`.
final class FakeStatementAccountFunding: StatementAccountFunding, @unchecked Sendable {
    private struct State {
        var calls: [AccountId] = []
        var failure: Error?
        var holdsNext = false
        var released = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var calls: [AccountId] { state.withLock { $0.calls } }

    func fail(with error: Error?) {
        state.withLock { $0.failure = error }
    }

    func holdNext() {
        state.withLock { $0.holdsNext = true }
    }

    func release() {
        state.withLock { $0.released = true }
    }

    func ensureFunded(accountId: AccountId, priority _: AllowanceRecord.Priority) async throws {
        let shouldHold = state.withLock { state in
            state.calls.append(accountId)
            defer { state.holdsNext = false }
            return state.holdsNext
        }

        while shouldHold, !state.withLock({ $0.released }) {
            await Task.yield()
        }

        if let failure = state.withLock({ $0.failure }) {
            throw failure
        }
    }
}
