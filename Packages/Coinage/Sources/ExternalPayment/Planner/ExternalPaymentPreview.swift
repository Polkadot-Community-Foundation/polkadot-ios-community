import Foundation

/// What an external payment would do, mirroring Android's `ExternalPaymentPlan`. Whether the plan
/// costs privacy is a separate question (`canPayPrivately`), not encoded here.
public enum ExternalPaymentPreview: Equatable {
    /// Vouchers already in a recycler cover the amount; they are unloaded as selected.
    case unloadVouchers([TrackedVoucher])
    /// `coins` are recycled first, then unloaded together with `exactVouchers`, which are every
    /// voucher the chain would accept.
    case loadCoins(coins: [TrackedCoin], exactVouchers: [TrackedVoucher])
    /// What the chain would accept cannot cover the amount.
    case notEnoughBalance

    public var vouchers: [TrackedVoucher] {
        switch self {
        case let .unloadVouchers(vouchers),
             let .loadCoins(_, vouchers):
            vouchers
        case .notEnoughBalance:
            []
        }
    }

    public var coins: [TrackedCoin] {
        if case let .loadCoins(coins, _) = self { return coins }
        return []
    }
}
