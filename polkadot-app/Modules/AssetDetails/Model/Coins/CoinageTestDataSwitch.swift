import DesignSystem
import PolkadotUI
import SwiftUI

// TODO: Remove. Scaffolding for reviewing the coin depiction against holdings the wallet cannot
// easily be put into. Everything the switch needs lives in this file, and removing it means
// deleting the file and the lines in `AssetDetailsViewLayout` marked with the same TODO.

/// Which set of holdings the coins draw.
enum CoinageTestDataMode: String, CaseIterable, Identifiable {
    case live
    case everyDenomination
    case everyStatus
    case randomFifty
    case randomFiveHundred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .everyDenomination: "All values"
        case .everyStatus: "All states"
        case .randomFifty: "50"
        case .randomFiveHundred: "500"
        }
    }

    /// `nil` draws whatever the wallet actually holds.
    var strip: [CoinageScene.Coin]? {
        switch self {
        case .live: nil
        case .everyDenomination: CoinageTestData.everyDenomination()
        case .everyStatus: CoinageTestData.everyStatus()
        case .randomFifty: CoinageTestData.random(count: 50, seed: 50)
        case .randomFiveHundred: CoinageTestData.random(count: 500, seed: 500)
        }
    }
}

/// The radio row itself.
struct CoinageTestDataSwitch: View {
    @Binding var mode: CoinageTestDataMode

    var body: some View {
        HStack(spacing: DSSpacings.small) {
            ForEach(CoinageTestDataMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    HStack(spacing: DSSpacings.extraTiny) {
                        Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 11))

                        Text(option.title)
                            .typography(.bodySmall)
                    }
                    .foregroundStyle(mode == option ? Color.fgPrimary : Color.fgSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Generators

enum CoinageTestData {
    private static let exponents: ClosedRange<Int16> = 0 ... CoinageCoinDesign.highestExponent

    /// One of every denomination, all as untraceable as a coin can be, so the switch shows the
    /// fifteen designs with nothing on top of them.
    static func everyDenomination() -> [CoinageScene.Coin] {
        exponents.map { coin(id: "test-value-\($0)", exponent: $0, level: CoinageWear.maximumLevel) }
    }

    /// Twenty holdings of one denomination across the whole wear ladder. A single value keeps metal
    /// and outline fixed, so the only thing changing is how traceable the holding is.
    static func everyStatus() -> [CoinageScene.Coin] {
        let exponent: Int16 = 4
        let count = 20

        return (0 ..< count).map { index in
            coin(
                id: "test-state-\(index)",
                exponent: exponent,
                level: CoinageWear.maximumLevel - index * CoinageWear.maximumLevel / (count - 1),
                isReady: index % 4 != 0
            )
        }
    }

    /// A wallet of no particular shape, for judging how the coins read in bulk. Seeded, so a given
    /// size always draws the same wallet and a change to the depiction is the only thing that moves.
    static func random(count: Int, seed: Int) -> [CoinageScene.Coin] {
        var noise = CoinageNoise(seed: "test-random-\(seed)")

        return (0 ..< count).map { index in
            let exponent = min(Int16(noise.next() * CGFloat(exponents.count)), exponents.upperBound)
            let level = min(
                Int(noise.next() * CGFloat(CoinageWear.maximumLevel + 1)),
                CoinageWear.maximumLevel
            )

            return coin(
                id: "test-random-\(seed)-\(index)",
                exponent: exponent,
                level: level,
                isReady: noise.next() > 0.25
            )
        }
    }

    private static func coin(
        id: String,
        exponent: Int16,
        level: Int,
        isReady: Bool = true
    ) -> CoinageScene.Coin {
        CoinageScene.Coin(
            id: id,
            exponent: exponent,
            wear: CoinageWear.amount(forLevel: level),
            partition: isReady ? .ready : .clearing,
            status: isReady ? "ready" : "recycling",
            level: level
        )
    }
}

/// Deterministic scatter, so a given test set draws the same wallet every time.
struct CoinageNoise {
    private var state: UInt64

    init(seed: String) {
        state = seed.unicodeScalars.reduce(UInt64(0x9E37_79B9_7F4A_7C15)) {
            ($0 &* 31) &+ UInt64($1.value)
        } | 1
    }

    mutating func next() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17

        return CGFloat(state % 100_000) / 100_000
    }
}

/// A zeroed breakdown, so the coinage card still draws on a wallet that holds no coinage and the
/// switch stays reachable there.
extension CoinageBalanceBreakdownViewModel {
    static let testDataPlaceholder = CoinageBalanceBreakdownViewModel(
        totalBalance: "0",
        availableNowBalance: "0",
        gainingPrivacyBalance: "0",
        symbol: "",
        composition: .empty,
        holdings: [],
        groups: [],
        distribution: .empty,
        matrix: .empty,
        strip: []
    )
}
