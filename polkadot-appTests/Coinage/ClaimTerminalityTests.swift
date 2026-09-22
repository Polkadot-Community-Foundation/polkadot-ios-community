import Coinage
import DurableTransactions
import Foundation
import SubstrateSdk
import Testing
@testable import polkadot_app

/// Whether an incoming claim is finished for good is read off the durability ledger, never off the
/// status the monitor last published. That status is written by the monitor's own catch, so a
/// transient chain read would otherwise record a permanence the system never reached — and a message
/// marked terminal is skipped on every later launch.
@Suite("Claim terminality")
struct ClaimTerminalityTests {
    private let coinA = Data(repeating: 0xA1, count: 32)
    private let coinB = Data(repeating: 0xB2, count: 32)

    /// The late-arrival case, and the one that matters most: the coins were not yet visible when an
    /// earlier pass ran, so nothing was registered. Nothing is settled, and the next launch retries.
    @Test("an empty group is not terminal")
    func emptyGroupIsNotTerminal() {
        #expect(!CoinageTransferMonitor.isClaimTerminal(entries: [], memoCoins: [coinA]))
    }

    @Test("a group with anything still live is not terminal")
    func liveEntryIsNotTerminal() {
        let entries = [entry(claiming: coinA, status: .pending)]

        #expect(!CoinageTransferMonitor.isClaimTerminal(entries: entries, memoCoins: [coinA]))
    }

    @Test("a settled group covering every coin is terminal")
    func settledGroupCoveringEveryCoinIsTerminal() {
        let entries = [
            entry(claiming: coinA, status: .finalizedSuccess),
            entry(claiming: coinB, status: .finalizedSuccess)
        ]

        #expect(CoinageTransferMonitor.isClaimTerminal(entries: entries, memoCoins: [coinA, coinB]))
    }

    /// A failed claim still counts as covered: the loop will not re-register it, so nothing further
    /// will happen for that coin. That is the C1 gap, recorded here rather than hidden.
    @Test("a settled group is terminal even where a claim failed")
    func failedClaimStillCounts() {
        let entries = [entry(claiming: coinA, status: .failure)]

        #expect(CoinageTransferMonitor.isClaimTerminal(entries: entries, memoCoins: [coinA]))
    }

    /// The clause that keeps a partly-registered group alive: coin B has no entry at all, so the claim
    /// loop still has work to do however coin A's entry settled.
    @Test("a coin with no entry naming it keeps the group open")
    func unregisteredCoinIsNotTerminal() {
        let entries = [entry(claiming: coinA, status: .finalizedSuccess)]

        #expect(!CoinageTransferMonitor.isClaimTerminal(entries: entries, memoCoins: [coinA, coinB]))
    }
}

private extension ClaimTerminalityTests {
    func entry(claiming coin: PublicKey, status: CoinageTxStatus) -> CoinageTxEntry {
        CoinageTxEntry(
            inputs: [.coin(.received(coin))],
            outputs: [],
            txHash: Data(repeating: 0x01, count: 32),
            checkpoint: BlockRef(number: 1, hash: Data(repeating: 0x02, count: 32)),
            mortality: 64,
            status: status
        )
    }
}
