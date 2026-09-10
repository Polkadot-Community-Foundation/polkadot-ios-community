import Foundation
import SubstrateSdk

struct ChainLiveness {
    private let windowSeconds: Double
    let slotCount: Int

    private var firstRecordedAt: Date?
    private var samples: [(height: BlockNumber, date: Date)] = []

    init(blockPeriod: Duration) {
        let blockSeconds = Self.durationToSeconds(blockPeriod)
        let calculatedWindow = max(30.0, blockSeconds * 10)

        windowSeconds = calculatedWindow
        slotCount = Int(calculatedWindow / blockSeconds)
    }

    mutating func record(height: BlockNumber, at date: Date) {
        if firstRecordedAt == nil {
            firstRecordedAt = date
        }

        samples.append((height: height, date: date))
        dropExpiredSamples(before: date)
    }

    func liveness(at date: Date) -> Double? {
        guard
            let firstRecorded = firstRecordedAt,
            date.timeIntervalSince(firstRecorded) >= windowSeconds,
            let oldestRetained = samples.first,
            let newestSample = samples.last else {
            return nil
        }

        let windowStart = date.addingTimeInterval(-windowSeconds)
        let anchor = samples.last { $0.date <= windowStart } ?? oldestRetained
        // BlockNumber is unsigned: a reorg deeper than the window puts the head below the
        // anchor, and the subtraction would trap before any clamp could run.
        let heightDelta = newestSample.height >= anchor.height
            ? newestSample.height - anchor.height
            : 0

        return min(1.0, Double(heightDelta) / Double(slotCount))
    }

    mutating func clear() {
        samples.removeAll()
        firstRecordedAt = nil
    }

    /// Retains the newest sample at or before the window start: it is the anchor the block count is
    /// measured from, so dropping it would let a stalled chain read as live.
    private mutating func dropExpiredSamples(before date: Date) {
        let windowStart = date.addingTimeInterval(-windowSeconds)

        guard let anchorIndex = samples.lastIndex(where: { $0.date <= windowStart }) else {
            return
        }

        samples.removeFirst(anchorIndex)
    }

    private static func durationToSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
