import Foundation
import os
import StatementStore
import SubstrateSdk
@testable import polkadot_app

/// Returns `signer` and records which contacts asked for the identity fallback.
final class FakeIdentitySigningFallback: NonPrivateSigningFallbacking, @unchecked Sendable {
    private let requests = OSAllocatedUnfairLock<[AccountId]>(initialState: [])
    let signer: StatementStoreSigning

    var contacts: [AccountId] { requests.withLock { $0 } }

    init(signer: StatementStoreSigning) {
        self.signer = signer
    }

    func identitySigner(for contactAccountId: AccountId, ownSignKeyId _: String) async throws -> StatementStoreSigning {
        requests.withLock { $0.append(contactAccountId) }
        return signer
    }
}
