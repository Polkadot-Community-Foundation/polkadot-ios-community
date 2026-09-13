import BigInt
import Foundation
import SDKLogger
import SubstrateSdk

/// Vouchers before coins, even ones still gaining privacy: a coin loaded only to be unloaded leaves
/// its recycler as soon as such a voucher would, so it saves no privacy and adds a recycling round.
///
/// 1. Private vouchers cover the amount → `.private`
/// 2. Every on-chain voucher covers it → `.lowPrivacy`, private ones first, then the largest
/// 3. Coins cover the shortfall → `.lowPrivacy` with all vouchers and the coins to recycle
/// 4. Otherwise → `.notEnoughBalance`
struct ExternalPaymentPlanner: ExternalPaymentPlanning {
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol
    private let classifier: ExternalPaymentAssetClassifier

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        classifier: ExternalPaymentAssetClassifier
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
        self.classifier = classifier
    }

    func plan(amount: Balance, context: DenominationBreakdownContext) async throws -> ExternalPaymentPreview {
        let buckets = try await classifier.voucherBuckets(voucherService.fetchAllTracked())

        let privateVouchers = buckets.usable
        if total(of: privateVouchers, context: context) >= amount {
            return .private(vouchers: pick(from: privateVouchers, target: amount, preferred: [], context: context))
        }

        let onChainVouchers = buckets.usable + buckets.gainingPrivacy
        let voucherTotal = total(of: onChainVouchers, context: context)
        if voucherTotal >= amount {
            let selected = pick(from: onChainVouchers, target: amount, preferred: privateVouchers, context: context)
            return .lowPrivacy(vouchers: selected, coins: [])
        }

        let deficit = amount - voucherTotal
        let coins = try await classifier.recyclableCoins(coinService.fetchAllTrackedCoins())
        guard total(of: coins, context: context) >= deficit else {
            return .notEnoughBalance
        }

        return .lowPrivacy(vouchers: onChainVouchers, coins: pick(from: coins, target: deficit, context: context))
    }

    func canPayPrivately(amount: Balance, context: DenominationBreakdownContext) async throws -> Bool {
        let buckets = try await classifier.voucherBuckets(voucherService.fetchAllTracked())
        return total(of: buckets.usable, context: context) >= amount
    }
}

// MARK: - Selection

private extension ExternalPaymentPlanner {
    func total(of vouchers: [TrackedVoucher], context: DenominationBreakdownContext) -> Balance {
        vouchers.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.voucher.exponent) }
    }

    func total(of coins: [TrackedCoin], context: DenominationBreakdownContext) -> Balance {
        coins.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
    }

    /// `preferred` vouchers first, then the largest, until `target` is reached.
    func pick(
        from vouchers: [TrackedVoucher],
        target: Balance,
        preferred: [TrackedVoucher],
        context: DenominationBreakdownContext
    ) -> [TrackedVoucher] {
        let preferredIndices = Set(preferred.map(\.voucher.derivationIndex))
        let sorted = vouchers.sorted { lhs, rhs in
            let lhsPreferred = preferredIndices.contains(lhs.voucher.derivationIndex)
            let rhsPreferred = preferredIndices.contains(rhs.voucher.derivationIndex)
            guard lhsPreferred == rhsPreferred else { return lhsPreferred }
            return context.valueInPlanks(for: lhs.voucher.exponent) > context.valueInPlanks(for: rhs.voucher.exponent)
        }

        return accumulate(sorted, target: target) { context.valueInPlanks(for: $0.voucher.exponent) }
    }

    func pick(from coins: [TrackedCoin], target: Balance, context: DenominationBreakdownContext) -> [TrackedCoin] {
        let sorted = coins.sorted {
            context.valueInPlanks(for: $0.coin.exponent) > context.valueInPlanks(for: $1.coin.exponent)
        }

        return accumulate(sorted, target: target) { context.valueInPlanks(for: $0.coin.exponent) }
    }

    func accumulate<Asset>(_ sorted: [Asset], target: Balance, value: (Asset) -> Balance) -> [Asset] {
        var selected: [Asset] = []
        var accumulated = Balance(0)

        for asset in sorted {
            if accumulated >= target { break }
            selected.append(asset)
            accumulated += value(asset)
        }

        return selected
    }
}
