import Foundation

/// What an external payment would spend, in the order the planner prefers: private vouchers alone,
/// then any on-chain voucher plus coins recycled for the shortfall.
public enum ExternalPaymentPreview: Equatable {
    /// Private vouchers cover the amount; nothing gives up privacy.
    case `private`(vouchers: [TrackedVoucher])
    /// Vouchers still gaining privacy and/or coins loaded only to be unloaded: `vouchers` are
    /// offboarded as they are, `coins` (possibly none) are recycled first.
    case lowPrivacy(vouchers: [TrackedVoucher], coins: [TrackedCoin])
    /// What the chain would accept cannot cover the amount.
    case notEnoughBalance

    public var isPrivate: Bool {
        if case .private = self { return true }
        return false
    }

    public var vouchers: [TrackedVoucher] {
        switch self {
        case let .private(vouchers),
             let .lowPrivacy(vouchers, _):
            vouchers
        case .notEnoughBalance:
            []
        }
    }

    public var coins: [TrackedCoin] {
        if case let .lowPrivacy(_, coins) = self { return coins }
        return []
    }
}
