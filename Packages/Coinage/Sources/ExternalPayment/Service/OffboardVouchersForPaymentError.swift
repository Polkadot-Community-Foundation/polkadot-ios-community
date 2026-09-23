import Foundation
import SubstrateSdk

enum OffboardVouchersForPaymentError: Error {
    case emptyVouchers
    case missingRecyclerInfo
    case unexpectedEmptyRevision(RecyclerKey)
    case noSurplusHost(Balance)
    /// The change owed back cannot be expressed in the instance's denominations, so no set of vouchers
    /// could carry it. Refused rather than silently overpaid to the destination.
    case surplusNotExpressible(Balance)
    case subscriptionEnded
    case unknownVoucher(CoinageKeyIndex)
}
