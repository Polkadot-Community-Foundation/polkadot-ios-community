import Foundation
import Individuality
import os
import SubstrateSdk

/// Records funding calls; `holdNext()` keeps the next call pending until `release()`.
final class FakeStatementAccountFunding: StatementAccountFunding, @unchecked Sendable {
    private struct State {
        var calls: [AccountId] = []
        var priorities: [AllowanceRecord.Priority] = []
        var failure: Error?
        var holdsNext = false
        var released = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var calls: [AccountId] { state.withLock { $0.calls } }
    var priorities: [AllowanceRecord.Priority] { state.withLock { $0.priorities } }

    func fail(with error: Error?) {
        state.withLock { $0.failure = error }
    }

    func holdNext() {
        state.withLock { $0.holdsNext = true }
    }

    func release() {
        state.withLock { $0.released = true }
    }

    func ensureFunded(
        accountId: AccountId,
        priority: AllowanceRecord.Priority,
        domain _: AllowanceRecord.Domain
    ) async throws {
        let shouldHold = state.withLock { state in
            state.calls.append(accountId)
            state.priorities.append(priority)
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
