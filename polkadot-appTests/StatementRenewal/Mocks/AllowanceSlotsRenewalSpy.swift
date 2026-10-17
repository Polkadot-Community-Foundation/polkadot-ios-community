import Foundation
import os

@testable import polkadot_app

/// Counts allowance renewals; with `holdsRenewal` each call parks until `releaseRenewals()`.
final class AllowanceSlotsRenewalSpy: AllowanceSlotsRenewing, @unchecked Sendable {
    private struct State {
        var callCount = 0
        var held: [CheckedContinuation<Void, Never>] = []
        var isHolding: Bool
    }

    private let state: OSAllocatedUnfairLock<State>

    init(holdsRenewal: Bool = false) {
        state = OSAllocatedUnfairLock(initialState: State(isHolding: holdsRenewal))
    }

    var callCount: Int {
        state.withLock(\.callCount)
    }

    func renewAllowanceSlots() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state -> Bool in
                state.callCount += 1
                guard state.isHolding else { return true }
                state.held.append(continuation)
                return false
            }

            if resumeNow {
                continuation.resume()
            }
        }
    }

    func releaseRenewals() {
        let held = state.withLock { state in
            state.isHolding = false
            defer { state.held = [] }
            return state.held
        }

        held.forEach { $0.resume() }
    }
}
