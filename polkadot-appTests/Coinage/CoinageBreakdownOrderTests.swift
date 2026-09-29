import Coinage
import Foundation
import Testing
@testable import polkadot_app

/// The fungibility ladder and the order it puts the breakdown rows in.
@Suite("Coinage breakdown ordering")
struct CoinageBreakdownOrderTests {
    // MARK: - The ladder

    @Test("Full fungibility is the shortest bar, none is the longest")
    func ladderEnds() {
        #expect(CoinageStatusMetrics.bucket(forScore: 100) == 0)
        #expect(CoinageStatusMetrics.bucket(forScore: 0) == CoinageStatusMetrics.maximumBucket)
        #expect(CoinageStatusMetrics.fraction(forBucket: 0) == 0)
        #expect(CoinageStatusMetrics.fraction(forBucket: CoinageStatusMetrics.maximumBucket) == 1)
    }

    @Test("Buckets widen as fungibility falls", arguments: [
        (100, 0), (66, 0), (65, 1), (43, 1), (42, 2), (28, 2),
        (27, 3), (19, 3), (18, 4), (12, 4), (11, 5), (8, 5),
        (7, 6), (5, 6), (4, 7), (2, 7), (1, 8), (0, 8)
    ])
    func ladder(score: Int, expected: Int) {
        #expect(CoinageStatusMetrics.bucket(forScore: UInt8(score)) == expected)
    }

    @Test("Every score lands in exactly one bucket, and the ladder never reverses")
    func ladderIsMonotonic() {
        let buckets = (0 ... 100).map { CoinageStatusMetrics.bucket(forScore: UInt8($0)) }

        #expect(Set(buckets) == Set(0 ... CoinageStatusMetrics.maximumBucket))
        #expect(buckets == buckets.sorted().reversed())
    }

    // MARK: - The batch penalty

    @Test("A single unload is scored on its recycler alone")
    func singleUnloadHasNoPenalty() {
        let coin = coin(age: 0, fungibility: 12)

        #expect(CoinageBreakdownFactory.bucket(for: coin) == 4)
    }

    @Test("A batch unload is pushed down the ladder")
    func batchUnloadIsPenalised() {
        let coin = coin(age: 1, fungibility: 12)

        #expect(CoinageBreakdownFactory.bucket(for: coin) == 4 + CoinageStatusMetrics.batchUnloadPenalty)
    }

    @Test("The penalty cannot push a coin past the end of the ladder")
    func penaltyClamps() {
        let coin = coin(age: 1, fungibility: 0)

        #expect(CoinageBreakdownFactory.bucket(for: coin) == CoinageStatusMetrics.maximumBucket)
    }

    @Test("A coin with no recycler record has no bucket")
    func unknownHistoryHasNoBucket() {
        let coin = coin(age: 3, fungibility: nil, hops: [.transfer(bundleSize: 4)])

        #expect(CoinageBreakdownFactory.bucket(for: coin) == nil)
    }

    // MARK: - The order

    @Test("Within one denomination: unknown histories lead, then known levels least fungible first")
    func orderWithinADenomination() {
        let holdings = CoinageHoldings(
            coins: [
                holding(coin(age: 2, fungibility: nil, hops: hops(2))),
                holding(coin(age: 5, fungibility: nil, hops: hops(5))),
                holding(coin(age: 0, fungibility: 100)),
                holding(coin(age: 0, fungibility: 20))
            ],
            vouchers: [holding(voucher(fungibility: 50))]
        )

        let expected: [Placement] = [
            .unknownHistory(5),
            .unknownHistory(2),
            .knownLevel(3),
            .knownLevel(1),
            .knownLevel(0)
        ]

        #expect(severities(of: holdings) == expected)
    }

    @Test("Denomination leads, largest first")
    func denominationLeads() {
        let holdings = CoinageHoldings(
            coins: [
                holding(coin(exponent: 3, age: 0, fungibility: 20)),
                holding(coin(exponent: 9, age: 0, fungibility: 20)),
                holding(coin(exponent: 6, age: 0, fungibility: 20))
            ],
            vouchers: []
        )

        #expect(CoinageBreakdownFactory.rows(from: holdings).map(\.exponent) == [9, 6, 3])
    }

    @Test("Denomination outranks fungibility, which only separates coins worth the same")
    func denominationOutranksFungibility() {
        let holdings = CoinageHoldings(
            coins: [
                holding(coin(exponent: 2, age: 4, fungibility: nil, hops: hops(4))),
                holding(coin(exponent: 9, age: 0, fungibility: 100))
            ],
            vouchers: []
        )

        // The small coin nobody can trace used to lead on being the least fungible thing in the
        // list. It is still the least fungible; it is no longer what the eye meets first.
        #expect(CoinageBreakdownFactory.rows(from: holdings).map(\.exponent) == [9, 2])
    }

    @Test("Coins built without a row behind them are still ordered, test sets among them")
    func anyListComesOutOrdered() {
        // The test-data switch builds scene coins directly rather than through `rows(from:)`, and
        // it is the only place the depiction is ever reviewed. `everyStatus` generates its states
        // most fungible first, the exact reverse of the rule, so this is not a hypothetical.
        for mode in CoinageTestDataMode.allCases {
            guard let coins = mode.strip else { continue }

            let clearing = coins.prefix { $0.partition == .clearing }
            let ready = coins.dropFirst(clearing.count)

            #expect(ready.allSatisfy { $0.partition == .ready }, "\(mode) interleaves the partitions")

            for block in [Array(clearing), Array(ready)] where !block.isEmpty {
                #expect(
                    block.map(\.exponent) == block.map(\.exponent).sorted(by: >),
                    "\(mode) does not run largest denomination first"
                )

                for run in Dictionary(grouping: block, by: \.exponent).values {
                    #expect(
                        run.map(\.level) == run.map(\.level).sorted(),
                        "\(mode) does not run least fungible first within a denomination"
                    )
                }
            }
        }
    }

    @Test("Least fungible leads within a denomination, deepest history among those")
    func fungibilityOrdersOneDenomination() {
        let coins = [
            scene(id: "clean", exponent: 5, level: 9, hops: 0),
            scene(id: "traced-once", exponent: 5, level: 0, hops: 1),
            scene(id: "traced-often", exponent: 5, level: 0, hops: 4),
            scene(id: "hiding", exponent: 5, level: 4, hops: 0)
        ]

        #expect(
            CoinageBreakdownFactory.inDisplayOrder(coins).map(\.id)
                == ["traced-often", "traced-once", "hiding", "clean"]
        )
    }

    @Test("A finer order set by the caller survives inside one denomination")
    func theOrderWithinADenominationIsKept() {
        let coins = (0 ..< 6).map {
            CoinageScene.Coin(
                id: "coin-\($0)", exponent: Int16($0 % 2), wear: 0,
                partition: .ready, status: "ready", level: 0, hops: 0
            )
        }

        // Exponent 1: coins 1, 3, 5 in that order. Exponent 0: coins 0, 2, 4.
        #expect(
            CoinageBreakdownFactory.inDisplayOrder(coins).map(\.id)
                == ["coin-1", "coin-3", "coin-5", "coin-0", "coin-2", "coin-4"]
        )
    }

    @Test("Partition outranks denomination, so the two blocks never interleave")
    func partitionOutranksDenomination() {
        let coins = [
            CoinageScene.Coin(
                id: "small-clearing", exponent: 2, wear: 1,
                partition: .clearing, status: "clearing", level: 0, hops: 0
            ),
            CoinageScene.Coin(
                id: "large-ready", exponent: 9, wear: 0,
                partition: .ready, status: "ready", level: 8, hops: 0
            ),
            CoinageScene.Coin(
                id: "large-clearing", exponent: 8, wear: 1,
                partition: .clearing, status: "clearing", level: 0, hops: 0
            )
        ]

        // Both clearing coins first even though one is worth less than the ready one, and the
        // larger of the two leads inside the block.
        #expect(
            CoinageBreakdownFactory.inDisplayOrder(coins).map(\.id)
                == ["large-clearing", "small-clearing", "large-ready"]
        )
    }
}

// MARK: - Fixtures

private extension CoinageBreakdownOrderTests {
    enum Placement: Equatable {
        case unknownHistory(Int)
        case knownLevel(Int)
    }

    func severities(of holdings: CoinageHoldings) -> [Placement] {
        CoinageBreakdownFactory.rows(from: holdings).map { row in
            switch row.standing {
            case .unknownHistory: .unknownHistory(row.severity)
            case .knownLevel: .knownLevel(row.severity)
            }
        }
    }

    /// One installation for the whole suite: ordering only ever compares items within it.
    static let installation = try! CoinageInstallationId(value: Data(repeating: 7, count: 32))

    func scene(id: String, exponent: Int16, level: Int, hops: Int) -> CoinageScene.Coin {
        CoinageScene.Coin(
            id: id,
            exponent: exponent,
            wear: CoinageWear.amount(forLevel: level),
            partition: .ready,
            status: "ready",
            level: level,
            hops: hops
        )
    }

    func keyIndex(_ item: DerivationIndex) -> CoinageKeyIndex {
        CoinageKeyIndex(installation: Self.installation, item: item)
    }

    func hops(_ count: Int) -> [Hop] {
        Array(repeating: .transfer(bundleSize: 1), count: count)
    }

    func coin(
        exponent: Int16 = 5,
        age: Int16,
        fungibility: UInt8?,
        hops: [Hop] = []
    ) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: keyIndex(DerivationIndex(abs(Int(age)) + Int(exponent) * 100)),
            age: age,
            recyclerFungibility: fungibility,
            hops: hops,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: Int(exponent)), count: 32)
        )
    }

    func voucher(exponent: Int16 = 5, fungibility: UInt8) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: keyIndex(900),
            allocatedAt: .distantPast,
            readyAt: .distantPast,
            remoteState: .inRecycler(.init(index: 0, membersCount: 10)),
            recyclerFungibility: fungibility,
            maxRecyclerFungibility: 100,
            publicKey: Data(repeating: 9, count: 32)
        )
    }

    func holding(_ coin: Coin) -> CoinageHoldings.CoinHolding {
        .init(coin: coin, availability: .availableNow)
    }

    func holding(_ voucher: Voucher) -> CoinageHoldings.VoucherHolding {
        .init(voucher: voucher, availability: .availableNow)
    }
}
