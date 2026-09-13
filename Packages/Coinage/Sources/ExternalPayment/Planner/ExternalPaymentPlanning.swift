import Foundation
import SubstrateSdk

/// Prefers funds that cost no privacy, then falls back to anything the chain would accept. A caller
/// that may reach the fallback confirms the privacy loss with the user first, see ``canPayPrivately``.
protocol ExternalPaymentPlanning: Sendable {
    func plan(amount: Balance, context: DenominationBreakdownContext) async throws -> ExternalPaymentPreview

    /// Whether ``plan`` would pay `amount` from private vouchers alone — the same check as its first
    /// step, so the warning and the plan cannot disagree.
    func canPayPrivately(amount: Balance, context: DenominationBreakdownContext) async throws -> Bool
}
