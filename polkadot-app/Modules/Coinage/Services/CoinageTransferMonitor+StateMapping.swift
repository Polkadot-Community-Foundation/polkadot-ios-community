import BigInt
import Coinage
import Foundation
import SubstrateSdk

extension CoinageTransferDetection {
    /// Projects the receiver's claim detection onto the persisted state. A partial claim is `claimed`
    /// with the shortfall visible against the message total; coins still being retried are plain
    /// `claiming` — the claimed-so-far amount is not persisted.
    var incomingState: IncomingTransferState {
        switch self {
        case .detecting:
            IncomingTransferState(status: .detecting)
        case .claiming,
             .claimingRest:
            IncomingTransferState(status: .claiming)
        case let .claimed(amount, _):
            IncomingTransferState(status: .claimed, actualValue: amount)
        case let .claimedPartially(claimed):
            IncomingTransferState(status: .claimed, actualValue: claimed)
        case .notClaimed:
            IncomingTransferState(status: .failed)
        }
    }
}

extension [PublicKey: CoinageTransferState] {
    /// Aggregates per-coin statuses into one message-level state. Mirrors Android's
    /// `toPaymentStatus`: any coin still to be taken keeps the message at `sending`/`sent`; once
    /// nothing is outstanding, the claimed value is final.
    func outgoingState(context: DenominationBreakdownContext) -> OutgoingTransferState {
        let states = Array(values)
        guard !states.isEmpty else { return OutgoingTransferState(status: .sending) }

        let claimed = states.filter { if case .claimed = $0.status { true } else { false } }
        let awaiting = states.filter { $0.status == .awaitingClaim }
        let outstanding = states.filter { $0.status == .awaitingClaim || $0.status == .detecting }

        if !outstanding.isEmpty {
            return OutgoingTransferState(status: awaiting.isEmpty && claimed.isEmpty ? .sending : .sent)
        }
        guard !claimed.isEmpty else { return OutgoingTransferState(status: .failed) }

        let amount = claimed.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
        return OutgoingTransferState(status: .claimed, actualValue: amount)
    }

    /// Every coin has reached a terminal status, so the subscription has nothing more to report.
    var isSettled: Bool {
        !isEmpty && values.allSatisfy(\.status.isTerminal)
    }
}
