import Foundation
import Testing
import SubstrateSdk
@testable import polkadot_app

struct ChainLivenessTests {
    @Test("Nil liveness with zero samples")
    func nilLivenessWithZeroSamples() {
        let liveness = ChainLiveness(blockPeriod: .seconds(2))

        #expect(liveness.liveness(at: Date()) == nil)
    }

    @Test("Nil liveness with one sample")
    func nilLivenessWithOneSample() {
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let date = Date()

        liveness.record(height: 0, at: date)

        #expect(liveness.liveness(at: date) == nil)
    }

    @Test("Full window of regular blocks reaches liveness 1")
    func fullWindowLiveness1() {
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let startDate = Date()

        for index in 0 ... 15 {
            liveness.record(height: BlockNumber(index), at: startDate.addingTimeInterval(Double(index) * 2))
        }

        #expect(liveness.liveness(at: startDate.addingTimeInterval(30)) == 1.0)
    }

    @Test("Stalled chain has liveness 0")
    func stalledChainLiveness0() {
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let startDate = Date()

        liveness.record(height: 0, at: startDate)
        liveness.record(height: 0, at: startDate.addingTimeInterval(30))

        #expect(liveness.liveness(at: startDate.addingTimeInterval(30)) == 0.0)
    }

    @Test("History shorter than window returns nil")
    func shorterThanWindowReturnsNil() {
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let startDate = Date()

        liveness.record(height: 0, at: startDate)
        liveness.record(height: 1, at: startDate.addingTimeInterval(5))

        #expect(liveness.liveness(at: startDate.addingTimeInterval(5)) == nil)
    }

    @Test("Window length 30s for fast chains")
    func window30sForFastChains() {
        let liveness = ChainLiveness(blockPeriod: .seconds(2))

        #expect(liveness.slotCount == 15)
    }

    @Test("Window length 60s for slow chains")
    func window60sForSlowChains() {
        let liveness = ChainLiveness(blockPeriod: .seconds(6))

        #expect(liveness.slotCount == 10)
    }

    @Test("Clear resets to nil")
    func clearResetsToNil() {
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let startDate = Date()

        for index in 0 ... 15 {
            liveness.record(height: BlockNumber(index), at: startDate.addingTimeInterval(Double(index) * 2))
        }

        liveness.clear()

        #expect(liveness.liveness(at: startDate.addingTimeInterval(30)) == nil)
    }

    @Test("Reorg moving head backward counts from the anchor")
    func reorgBackwardGuarded() {
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let startDate = Date()

        liveness.record(height: 10, at: startDate)
        liveness.record(height: 9, at: startDate.addingTimeInterval(2))
        liveness.record(height: 11, at: startDate.addingTimeInterval(4))

        // Anchor is height 10 at the window start, head is 11: one block in 15 slots.
        #expect(liveness.liveness(at: startDate.addingTimeInterval(30)) == 1.0 / 15.0)
    }

    @Test("Head below the anchor height reads liveness 0 without trapping")
    func headBelowAnchorHeight() {
        // BlockNumber is unsigned, so an unguarded subtraction here traps and kills the run.
        var liveness = ChainLiveness(blockPeriod: .seconds(2))
        let startDate = Date()

        liveness.record(height: 10, at: startDate)
        liveness.record(height: 5, at: startDate.addingTimeInterval(2))

        #expect(liveness.liveness(at: startDate.addingTimeInterval(30)) == 0.0)
    }
}
