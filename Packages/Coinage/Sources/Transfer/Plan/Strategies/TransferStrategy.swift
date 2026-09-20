import Foundation

/// The outcome of a strategy's foreground preparation.
///
/// `prepare` does everything that must complete before the memo — the keys — can leave the device:
/// mint the outputs and reserve the handoff. It builds and submits nothing: the transactions come back
/// to be scheduled inside the transaction that makes the payment durable, and are built by their
/// policies afterwards.
struct PreparedStrategy {
    /// Memo entries for the coins the recipient receives — built from what `prepare` minted.
    let memoEntries: [PlannedMemoEntry]
    let handoffCommit: any CoinageHandoffCommit

    /// Still to be scheduled. Empty for a strategy that puts nothing of ours on chain.
    let transactions: [CoinageScheduledTxRequest]
}

/// Protocol for transfer execution strategies. Each strategy mints its outputs and pre-commits the
/// handoff, and declares the transactions that will spend them.
protocol TransferStrategy {
    /// Mints outputs (persisted by the allocator) and pre-commits the handoff. Returns the memo
    /// entries, the handoff handle, and the transactions still to be scheduled.
    func prepare(groupId: CoinageTxGroupId?) async throws -> PreparedStrategy
}
