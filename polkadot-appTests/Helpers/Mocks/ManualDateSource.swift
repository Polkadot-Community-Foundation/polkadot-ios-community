import Foundation

/// A synchronous date source that only moves when a test advances it; pass `{ dateSource.now }` where a
/// `() -> Date` is injected. Use `MockDateProvider` for the async `DateProviding` seam instead.
final class ManualDateSource: @unchecked Sendable {
    private(set) var now: Date

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }
}
