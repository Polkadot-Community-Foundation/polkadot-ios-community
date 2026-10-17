import BigInt
import Foundation
import Testing
@testable import Coinage

/// The awaited pass a background task runs: one complete evaluation of the current wallet, recycling what it gates.
struct CoinRecyclingEvaluatorPassTests {
    private let context = DenominationBreakdownContext(
        unit: BigUInt(1_000_000),
        precision: 6,
        maxExponent: 7,
        minExponent: -6
    )

    @Test func passRecyclesGatedCoinsAndReportsCounts() async {
        let database = StubDatabaseDependencyFactory()
        database.trackedCoins.send([coin(index: 0, age: CoinageConstants.recycleAtAge), coin(index: 1, age: 0)])
        database.trackedVouchers.send([])
        let recyclingService = RecyclingServiceSpy()

        let outcome = await makeEvaluator(database: database, recyclingService: recyclingService).evaluateNow()

        #expect(outcome == .completed(evaluatedCoins: 2, gated: 1, submitted: 1))
        #expect(await recyclingService.recycledBatches.map { $0.map(\.derivationIndex) } == [[0]])
    }

    @Test func passWithNothingGatedSubmitsNothing() async {
        let database = StubDatabaseDependencyFactory()
        database.trackedCoins.send([coin(index: 0, age: 0)])
        database.trackedVouchers.send([])
        let recyclingService = RecyclingServiceSpy()

        let outcome = await makeEvaluator(database: database, recyclingService: recyclingService).evaluateNow()

        #expect(outcome == .completed(evaluatedCoins: 1, gated: 0, submitted: 0))
        #expect(await recyclingService.recycledBatches.isEmpty)
    }

    @Test func passPublishesItsVerdicts() async {
        let database = StubDatabaseDependencyFactory()
        database.trackedCoins.send([coin(index: 0, age: CoinageConstants.recycleAtAge)])
        database.trackedVouchers.send([])
        let evaluator = makeEvaluator(database: database, recyclingService: RecyclingServiceSpy())

        _ = await evaluator.evaluateNow()

        #expect(evaluator.currentVerdicts()?[0]?.triggersRecycling == true)
    }
}

private extension CoinRecyclingEvaluatorPassTests {
    func makeEvaluator(
        database: StubDatabaseDependencyFactory,
        recyclingService: RecyclingServiceSpy
    ) -> CoinRecyclingEvaluator {
        CoinRecyclingEvaluator(
            databaseFactory: database,
            settings: StubRecyclingStrategySettings(strategy: .balanced),
            strategyProvider: StubRecyclingStrategyProvider(),
            ringCapacityProvider: StubRingCapacityProvider(capacities: [:]),
            preClassificator: CoinageAssetPreClassificator(),
            recyclingService: recyclingService,
            denominationContext: context,
            logger: nil
        )
    }

    func coin(index: CoinageKeyIndex, age: Int16) -> TrackedCoin {
        let coin = Coin(
            exponent: 1,
            derivationIndex: index,
            age: age,
            isOnchain: true,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index.item), count: 32)
        )
        let free = CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: nil)
        return TrackedCoin(coin: coin, state: free)
    }
}
