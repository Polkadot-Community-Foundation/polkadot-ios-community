import Foundation
import os
@testable import polkadot_app

final class StubChatActivityProvider: ChatActivityProviding, @unchecked Sendable {
    private let activity: ChatActivity
    private let lastCutoff = OSAllocatedUnfairLock<Date?>(initialState: nil)

    init(activity: ChatActivity) {
        self.activity = activity
    }

    var requestedCutoff: Date? { lastCutoff.withLock { $0 } }

    func activity(since cutoff: Date) async throws -> ChatActivity {
        lastCutoff.withLock { $0 = cutoff }
        return activity
    }
}
