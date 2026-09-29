import CoreGraphics
import Foundation

/// Where every coin is heading, for one of the two arrangements.
///
/// The strip and the grid are the same coins in different places, so this hands the field a set of
/// targets and nothing else changes. A toggle between them is a retarget, which is why the coins
/// fly rather than cut.
enum CoinageArrangement {
    case strip
    case grid

    struct Result {
        let targets: [(coin: CoinageScene.Coin, target: CoinageCoinField.Target)]
        /// What the view needs to be tall enough for.
        let height: CGFloat
        /// Where each partition's header sits, for the labels over the grid.
        let blocks: [CoinageGridLayout.Block]
    }

    static func targets(
        for coins: [CoinageScene.Coin],
        arrangement: CoinageArrangement,
        area: CGSize,
        designs: [CoinageAssetStore.Design],
        stripHeight: CGFloat
    ) -> Result {
        switch arrangement {
        case .strip: strip(coins, width: area.width, designs: designs, height: stripHeight)
        case .grid: grid(coins, area: area, designs: designs)
        }
    }

    static func design(
        for coin: CoinageScene.Coin,
        in designs: [CoinageAssetStore.Design]
    ) -> CoinageAssetStore.Design? {
        designs[safe: min(max(Int(coin.exponent), 0), designs.count - 1)]
    }
}

// MARK: - Strip

private extension CoinageArrangement {
    static func strip(
        _ coins: [CoinageScene.Coin],
        width: CGFloat,
        designs: [CoinageAssetStore.Design],
        height: CGFloat
    ) -> Result {
        var options = CoinageStripLayout.Options()
        options.height = height

        let layout = CoinageStripLayout.layout(
            coins.map { coin in
                CoinageStripLayout.Coin(
                    size: CoinageCoinDesign.design(forExponent: coin.exponent).size,
                    width: CoinageScene.geometry(forExponent: coin.exponent).faceWidth,
                    thickness: CGFloat(design(for: coin, in: designs)?.thickness ?? 0.075),
                    partition: coin.partition
                )
            },
            width: width,
            options: options
        )

        let targets = zip(coins, layout.coins).map { coin, placement in
            (
                coin,
                CoinageCoinField.Target(
                    centre: placement.centre,
                    height: placement.height,
                    turn: placement.turn,
                    thickness: placement.thickness
                        / CGFloat(design(for: coin, in: designs)?.thickness ?? 0.075),
                    wear: coin.wear,
                    // The strip skips the six-tap luster path; the grid does not.
                    luster: 0,
                    calm: CoinageStripLayout.edgeCalm(turn: placement.turn)
                )
            )
        }

        return Result(targets: targets, height: height, blocks: [])
    }
}

// MARK: - Grid

private extension CoinageArrangement {
    static func grid(
        _ coins: [CoinageScene.Coin],
        area: CGSize,
        designs: [CoinageAssetStore.Design]
    ) -> Result {
        let byId = Dictionary(coins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let layout = CoinageGridLayout.layout(
            coins.map {
                CoinageGridLayout.Item(
                    id: $0.id,
                    exponent: $0.exponent,
                    partition: $0.partition,
                    status: $0.status,
                    level: $0.level
                )
            },
            area: area
        )

        var targets: [(coin: CoinageScene.Coin, target: CoinageCoinField.Target)] = []

        for cell in layout.cells {
            targets += cellTargets(cell, layout: layout, coins: byId, designs: designs)
        }

        return Result(targets: targets, height: layout.height, blocks: layout.blocks)
    }

    /// A cell holds one coin, or a pile of alike ones tipped back so their edges show. Coins past
    /// the fifth in a pile sit under the ones on top and are never drawn.
    static func cellTargets(
        _ cell: CoinageGridLayout.Cell,
        layout: CoinageGridLayout.Layout,
        coins: [String: CoinageScene.Coin],
        designs: [CoinageAssetStore.Design]
    ) -> [(coin: CoinageScene.Coin, target: CoinageCoinField.Target)] {
        let members = cell.ids.compactMap { coins[$0] }

        guard let first = members.first else { return [] }

        let height = layout.diameter * CoinageCoinDesign.design(forExponent: first.exponent).size

        guard cell.count > 1 else {
            return [(first, single(first, centre: cell.centre, height: height))]
        }

        let pile = CoinageGridLayout.pile(
            count: cell.count,
            height: height,
            thickness: CGFloat(design(for: first, in: designs)?.thickness ?? 0.075)
        )

        return members.enumerated().map { position, coin in
            let depth = min(position, pile.shown - 1)

            return (
                coin,
                CoinageCoinField.Target(
                    centre: CGPoint(
                        x: cell.centre.x,
                        y: cell.centre.y + CGFloat(depth) * pile.step
                    ),
                    height: height,
                    turn: 0,
                    // Negative tips the top away, which is what makes a pile read as stacked.
                    tilt: -CoinageGridLayout.Pile.tilt,
                    thickness: CoinageGridLayout.Pile.thicken,
                    wear: coin.wear,
                    luster: 1,
                    calm: 0,
                    lift: -CGFloat(depth) * pile.depthStep,
                    isHidden: position >= pile.shown
                )
            )
        }
    }

    static func single(
        _ coin: CoinageScene.Coin,
        centre: CGPoint,
        height: CGFloat
    ) -> CoinageCoinField.Target {
        CoinageCoinField.Target(
            centre: centre,
            height: height,
            turn: 0,
            thickness: 1,
            wear: coin.wear,
            luster: 1,
            calm: 0
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
