import Foundation

/// Stands in for the system microphone prompt and counts how often it was raised.
final class RecordPermissionRequesterSpy: @unchecked Sendable {
    private let grants: Bool
    private let lock = NSLock()
    private var count = 0

    init(grants: Bool) {
        self.grants = grants
    }

    var requestCount: Int {
        lock.withLock { count }
    }

    func request() -> Bool {
        lock.withLock { count += 1 }
        return grants
    }
}
