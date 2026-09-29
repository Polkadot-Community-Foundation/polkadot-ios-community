import BigInt
import Coinage
import CoreGraphics
import Foundation

/// Turns a classified ``CoinageHoldings`` snapshot into what the breakdown draws: the ordered
/// rows and the summary bar's three shares.
///
/// Pure and free of the presenter's state, so the ordering and the value weighting can be
/// exercised directly.
enum CoinageBreakdownFactory {
    /// Which half of a denomination's run a row belongs to. Holdings whose recycler we have no
    /// record of are the least fungible thing we can say anything about, so they lead.
    enum Standing: Int, Equatable {
        case unknownHistory = 0
        case knownLevel = 1
    }

    /// A row before pricing: what it takes to order it and to draw it.
    struct Row: Equatable {
        let id: String
        let exponent: Int16
        let standing: Standing
        /// Descending within a standing: hop count for ``Standing/unknownHistory``, fungibility
        /// bucket for ``Standing/knownLevel``. Both read "least fungible first", which now only
        /// separates holdings of the same denomination.
        let severity: Int
        let derivationIndex: CoinageKeyIndex
        /// How worn the holding is drawn as a coin. `0` is untraceable, `1` is fully traceable.
        let wear: CGFloat
        /// Spendable now, as opposed to still clearing. The strip keeps the two in separate runs.
        let isReady: Bool
        let status: CoinageHoldingStatus
    }

    /// One list, ordered by denomination, largest first.
    ///
    /// Partition comes before any of this and is applied by ``inDisplayOrder``, which is stable, so
    /// the whole order reads: Clearing before Ready, then by denomination, and only within one
    /// denomination by how fungible a holding is — unknown histories first, then by bucket. A
    /// derivation index breaks the last tie so equal holdings keep their order across refreshes.
    ///
    /// Fungibility used to lead, which is what the stakeholder asked for before the partitions
    /// existed. With them it put a one-cent coin nobody can trace ahead of the largest coin in the
    /// same partition, and the eye had nothing to hold on to.
    static func rows(from holdings: CoinageHoldings) -> [Row] {
        let coinRows = holdings.coins.map { holding in
            let bucket = bucket(for: holding.coin)

            return Row(
                id: "coin-\(holding.coin.derivationIndex)",
                exponent: holding.coin.exponent,
                standing: bucket == nil ? .unknownHistory : .knownLevel,
                severity: bucket ?? holding.coin.hops.count,
                derivationIndex: holding.coin.derivationIndex,
                wear: wear(
                    forScore: holding.coin.recyclerFungibility,
                    isBatchUnloaded: holding.coin.hops.isEmpty && holding.coin.age == 1
                ),
                isReady: holding.availability.displayBucket == .ready,
                status: .coin(
                    CoinStatusView.Model(
                        hopDots: holding.coin.hops.map(innerDots(for:)),
                        bucket: bucket,
                        isSpendable: holding.isAvailableNow
                    )
                )
            )
        }

        let voucherRows = holdings.vouchers.map { holding in
            let bucket = CoinageStatusMetrics.bucket(forScore: holding.voucher.recyclerFungibility)

            return Row(
                id: "voucher-\(holding.voucher.derivationIndex)",
                exponent: holding.voucher.exponent,
                standing: .knownLevel,
                severity: bucket,
                derivationIndex: holding.voucher.derivationIndex,
                wear: wear(forScore: holding.voucher.recyclerFungibility, isBatchUnloaded: false),
                isReady: holding.availability.displayBucket == .ready,
                status: .voucher(
                    VoucherStatusView.Model(
                        maxBucket: CoinageStatusMetrics.bucket(
                            forScore: holding.voucher.maxRecyclerFungibility
                        ),
                        bucket: bucket,
                        isUnloadable: holding.isAvailableNow
                    )
                )
            )
        }

        // Value is `unit * 2^exponent`, so ordering by exponent is exactly ordering by value.
        return (coinRows + voucherRows).sorted { lhs, rhs in
            if lhs.exponent != rhs.exponent {
                return lhs.exponent > rhs.exponent
            }

            if lhs.standing != rhs.standing {
                return lhs.standing.rawValue < rhs.standing.rawValue
            }

            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }

            return lhs.derivationIndex < rhs.derivationIndex
        }
    }

    /// One depiction and the holdings that share it.
    struct Group: Equatable {
        let id: String
        let status: CoinageHoldingStatus
        /// Exponents in display order, one per holding, so a caller can price them and total them.
        let exponents: [Int16]
    }

    /// Folds runs of identical depictions. Rows arrive ordered, so anything that draws the same is
    /// already adjacent and this is a scan. Two rows merge exactly when their status compares
    /// equal, which is the condition under which they would otherwise draw the same row twice.
    static func group(_ rows: [Row]) -> [Group] {
        rows.reduce(into: [Group]()) { groups, row in
            if let last = groups.last, last.status == row.status {
                groups[groups.count - 1] = Group(
                    id: last.id,
                    status: last.status,
                    exponents: last.exponents + [row.exponent]
                )
            } else {
                groups.append(Group(id: row.id, status: row.status, exponents: [row.exponent]))
            }
        }
    }

    /// Payments a holding has been through, which the face shows as pits. A voucher sitting in a
    /// recycler has been through none.
    private static func hops(for status: CoinageHoldingStatus) -> Int {
        switch status {
        case let .coin(model): model.hopDots.count
        case .voucher: 0
        }
    }

    /// How worn a holding is drawn, from the size of the crowd its recycler hides it in.
    ///
    /// The stored score is a share of ring capacity, so it converts back to a crowd size before it
    /// goes on the doubling scale the depiction uses. Without a recycler record nothing can be
    /// credited, and the holding wears as though it hides among nobody.
    static func wear(forScore score: UInt8?, isBatchUnloaded: Bool) -> CGFloat {
        guard let score else { return CoinageWear.unknown }

        let crowd = Int(CGFloat(min(score, CoinageConstants.fullFungibility))
            / CGFloat(CoinageConstants.fullFungibility)
            * CGFloat(CoinageWear.ringCapacity - 1))
        let penalty = isBatchUnloaded ? CoinageStatusMetrics.batchUnloadPenalty : 0

        return CoinageWear.amount(forLevel: max(CoinageWear.level(hiddenAmong: crowd) - penalty, 0))
    }

    /// One coin per holding for the summary strip. Clearing leads, as the reference orders it, so
    /// the two runs stay in the same places whether the strip is face on or edge on.
    static func stripCoins(_ rows: [Row]) -> [CoinageScene.Coin] {
        inDisplayOrder(
            rows.map {
                CoinageScene.Coin(
                    id: $0.id,
                    exponent: $0.exponent,
                    wear: $0.wear,
                    partition: $0.isReady ? .ready : .clearing,
                    status: $0.isReady ? "ready" : "clearing",
                    level: CoinageWear.level(forAmount: $0.wear),
                    hops: hops(for: $0.status)
                )
            }
        )
    }

    /// The whole order coins are drawn in: Clearing before Ready, then largest denomination first,
    /// then least fungible first, and deepest history first among those.
    ///
    /// The first two keys are the stakeholder's; the rest is what ``rows(from:)`` settles for live
    /// holdings, restated over what a ``CoinageScene/Coin`` carries so that it holds for any list.
    /// A holding nobody can trace wears as though it hides among nobody, which puts it at level
    /// zero and so at the front, exactly where its unknown history puts it upstream.
    ///
    /// Stating it twice is the point. Anything assembled without a row behind it — the test-data
    /// switch, which is the only place the depiction is ever reviewed — used to reach the layout
    /// with nothing but the partitions split, and came out in whatever order it was generated in.
    /// One of those sets runs its states most fungible first, the exact reverse of the rule.
    ///
    /// Stable, so live holdings are unaffected: they arrive in this order already, and a sort by
    /// the same keys cannot move them.
    ///
    /// Both layouts start a new block wherever the partition changes, so coins arriving interleaved
    /// would produce a block, and a header, per coin.
    static func inDisplayOrder(_ coins: [CoinageScene.Coin]) -> [CoinageScene.Coin] {
        let ordered = coins.enumerated().sorted { lhs, rhs in
            if lhs.element.partition != rhs.element.partition {
                return lhs.element.partition == .clearing
            }

            if lhs.element.exponent != rhs.element.exponent {
                return lhs.element.exponent > rhs.element.exponent
            }

            // Level counts the doublings of the crowd a coin hides in, so the lowest is the one
            // that hides among fewest and wears hardest.
            if lhs.element.level != rhs.element.level {
                return lhs.element.level < rhs.element.level
            }

            if lhs.element.hops != rhs.element.hops {
                return lhs.element.hops > rhs.element.hops
            }

            // Swift's sort is not stable, so the original position is the last word.
            return lhs.offset < rhs.offset
        }

        return ordered.map(\.element)
    }

    /// Where a depiction sits on the fungibility ladder.
    static func band(for status: CoinageHoldingStatus) -> Int {
        switch status {
        case let .coin(model):
            model.bucket ?? CoinageFungibilityDistribution.unknownBand
        case let .voucher(model):
            model.bucket
        }
    }

    /// The bucket a coin's bar is drawn at, or `nil` when we have no record of its recycler.
    ///
    /// A coin that left in a batch is linked to everything that left with it, which the recycler's
    /// own score knows nothing about, so it is pushed down the ladder. The batch is not recorded,
    /// but it is identifiable: the chain only hands out age 1 on a batch unload, and a single
    /// unload leaves age 0.
    static func bucket(for coin: Coin) -> Int? {
        guard let fungibility = coin.recyclerFungibility else { return nil }

        let base = CoinageStatusMetrics.bucket(forScore: fungibility)

        guard coin.hops.isEmpty, coin.age == 1 else { return base }

        return min(base + CoinageStatusMetrics.batchUnloadPenalty, CoinageStatusMetrics.maximumBucket)
    }

    /// Value-weighted split for the summary bar, bucketed exactly as the figures above it are:
    /// every holding lands in one of the two display buckets regardless of whether it is a coin or
    /// a voucher, so the bar's two shares account for the whole balance and nothing falls out.
    static func composition(
        of holdings: CoinageHoldings,
        context: DenominationBreakdownContext
    ) -> CoinageCompositionBar.Model {
        let planks = planksByAvailability(of: holdings) {
            context.valueInPlanks(for: $0)
        }
        let total = planks.total

        guard total > 0 else { return .empty }

        // Scaled integer division keeps this exact for plank counts far beyond Double.
        func share(_ part: BigUInt) -> Double {
            let scale = BigUInt(1_000_000)
            return Double(part * scale / total) / Double(scale)
        }

        return CoinageCompositionBar.Model(
            availableNowShare: share(planks.availableNow),
            gainingPrivacyShare: share(planks.gainingPrivacy)
        )
    }

    /// Plank totals per bucket. A named type rather than a tuple, so the two stay labelled
    /// wherever they travel.
    private struct BucketPlanks {
        var availableNow = BigUInt(0)
        var gainingPrivacy = BigUInt(0)

        var total: BigUInt { availableNow + gainingPrivacy }
    }

    private static func planksByAvailability(
        of holdings: CoinageHoldings,
        value: (Int16) -> BigUInt
    ) -> BucketPlanks {
        var planks = BucketPlanks()

        func add(_ availability: CoinageAvailability, _ amount: BigUInt) {
            switch availability.displayBucket {
            case .ready: planks.availableNow += amount
            case .clearing: planks.gainingPrivacy += amount
            }
        }

        for holding in holdings.coins {
            add(holding.availability, value(holding.coin.exponent))
        }

        for holding in holdings.vouchers {
            add(holding.availability, value(holding.voucher.exponent))
        }

        return planks
    }

    /// Inner dots for a hop: one per sibling it moved or was produced alongside.
    private static func innerDots(for hop: Hop) -> Int {
        switch hop {
        case let .transfer(bundleSize):
            CoinageStatusMetrics.innerDots(forCount: bundleSize)
        case let .split(fanout):
            CoinageStatusMetrics.innerDots(forCount: fanout)
        }
    }
}

/// The amounts shown above the summary bar. The bar draws two of them: available now and gaining
/// privacy. Pending is money that has not arrived yet and cannot be spent.
struct CoinageAmounts: Equatable {
    let total: Decimal
    let availableNow: Decimal
    /// Everything still clearing, which is what the user is shown: the domain's gaining-privacy
    /// and pending buckets both land here, so this and ``availableNow`` account for the total.
    let gainingPrivacy: Decimal

    static let zero = CoinageAmounts(total: 0, availableNow: 0, gainingPrivacy: 0)

    var hasFundsNotReady: Bool {
        gainingPrivacy > 0
    }
}
