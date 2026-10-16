import Foundation
import os
import StatementStore
import SubstrateSdk
@testable import polkadot_app

/// Returns `signer` (or declines) and records which contacts asked for the identity fallback.
final class FakeIdentitySigningFallback: NonPrivateSigningFallbacking, @unchecked Sendable {
    private struct State {
        var contacts: [AccountId] = []
        var declines = false
        var hasConsent = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    let signer: StatementStoreSigning

    var contacts: [AccountId] { state.withLock { $0.contacts } }

    init(signer: StatementStoreSigning) {
        self.signer = signer
    }

    func decline() {
        state.withLock { $0.declines = true }
    }

    func grantConsent() {
        state.withLock { $0.hasConsent = true }
    }

    func identitySigner(for contactAccountId: AccountId, ownSignKeyId _: String) async throws -> StatementStoreSigning {
        let declines = state.withLock { state in
            state.contacts.append(contactAccountId)
            return state.declines
        }

        if declines {
            throw ChatSigningConsentError.declined
        }

        return signer
    }

    func consentedSigner(for _: AccountId, ownSignKeyId _: String) async throws -> StatementStoreSigning? {
        state.withLock { $0.hasConsent } ? signer : nil
    }
}
