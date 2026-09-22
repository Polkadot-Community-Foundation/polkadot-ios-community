import Foundation

/// What the receiver knows about one incoming coinage payment that the durability ledger does not:
/// when this device first tried to claim it.
///
/// The claim window used to be anchored to `message.timestamp` — the *sender's* wall clock, carried on
/// the wire and compared against the receiver's own. Two devices' clocks decided how long a payment
/// could be claimed for, and a message first seen after that window had already elapsed was registered
/// with a deadline in the past, which the submission policy reads as "proven absent" on its first look.
/// Anchoring to this device's first attempt removes the cross-device comparison entirely.
protocol ClaimTransferStoring: Sendable {
    /// When this device first tried to claim `messageId`, writing "now" the first time it is asked.
    ///
    /// Idempotent and stable: the read and the insert are one transaction, so two launches racing
    /// cannot split the anchor, and every later call returns the anchor the first one wrote.
    func firstAttempt(for messageId: String) async throws -> Date
}
