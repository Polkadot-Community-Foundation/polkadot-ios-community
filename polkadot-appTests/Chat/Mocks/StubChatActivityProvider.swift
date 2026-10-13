import Foundation
import os
import SubstrateSdk
@testable import polkadot_app

final class StubChatActivityProvider: ChatActivityProviding, @unchecked Sendable {
    private let activePeers: Set<AccountId>
    private let lastCutoff = OSAllocatedUnfairLock<Date?>(initialState: nil)

    init(activePeers: Set<AccountId>) {
        self.activePeers = activePeers
    }

    var requestedCutoff: Date? { lastCutoff.withLock { $0 } }

    func activePeers(since cutoff: Date) async throws -> Set<AccountId> {
        lastCutoff.withLock { $0 = cutoff }
        return activePeers
    }
}
