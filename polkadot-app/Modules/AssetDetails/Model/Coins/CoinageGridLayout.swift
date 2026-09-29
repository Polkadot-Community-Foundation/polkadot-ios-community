import CoreGraphics
import Foundation

/// The coin grid: coins face on, packed in offset rows like a honeycomb, in the same order as the
/// strip, one block per partition under its header.
///
/// Ported line for line from `src/layout/hexgrid.js` and checked against the reference's own
/// conformance vectors. The pitch is as tight as fits; when even the smallest pitch will not hold
/// every coin singly, runs of alike coins stack into piles.
enum CoinageGridLayout {
    struct Options: Equatable {
        var maxDiameter: CGFloat = 52
        var minDiameter: CGFloat = 28
        var gap: CGFloat = 5
        var header: CGFloat = 34
        var blockGap: CGFloat = 14
        /// Coins drawn in a pile; the rest sit hidden under them.
        var stackShow: Int = 5

        init() {}
    }

    /// One holding, as much of it as the packing needs.
    struct Item: Equatable {
        let id: String
        let exponent: Int16
        let partition: CoinageStripLayout.Partition
        /// What keeps two clearing coins apart: recycling now, or still to be recycled.
        let status: String
        /// How hidden the coin is, on the doubling ladder.
        let level: Int
    }

    struct Cell: Equatable {
        let ids: [String]
        let count: Int
        let centre: CGPoint
    }

    struct Block: Equatable {
        let partition: CoinageStripLayout.Partition
        let top: CGFloat
        let count: Int
    }

    struct Layout: Equatable {
        let diameter: CGFloat
        let pitch: CGFloat
        let columns: Int
        let cells: [Cell]
        let blocks: [Block]
        let height: CGFloat
        let fits: Bool
    }

    /// A pile of `count` coins, tipped back so the edges show, one band per coin.
    ///
    /// Thickness is exaggerated because true thickness gives about a pixel a coin at grid sizes,
    /// which no one can count.
    enum Pile {
        static let tilt: CGFloat = 0.5
        static let thicken: CGFloat = 2.2
    }

    struct PileLayout: Equatable {
        let shown: Int
        let thickness: CGFloat
        /// How far down the next coin's edge sits.
        let step: CGFloat
        /// How far forward it sits, which is what orders them.
        let depthStep: CGFloat
        let height: CGFloat
    }

    static func pile(
        count: Int,
        height: CGFloat,
        thickness: CGFloat,
        show: Int = Options().stackShow
    ) -> PileLayout {
        let shown = min(count, show)
        let thick = thickness * Pile.thicken
        let step = thick * height * sin(Pile.tilt)

        return PileLayout(
            shown: shown,
            thickness: thick,
            step: step,
            depthStep: thick * height * cos(Pile.tilt),
            height: CGFloat(shown - 1) * step
        )
    }

    /// Bands for grouping: 256 or more others, 16 or more, fewer. Neighbouring levels look the
    /// same, so piles group by band rather than by level.
    static func hiddenBand(level: Int) -> Int {
        if level >= 9 {
            2
        } else if level >= 5 {
            1
        } else {
            0
        }
    }

    /// Laying out with `stacking` off keeps every coin its own cell, however many there are: the
    /// grid simply grows taller and scrolls. The reference stacks runs of alike coins once the
    /// smallest pitch stops fitting, and the port keeps that code and its vectors, but the app does
    /// not ask for it — a stack of two reads as one oddly thick coin and answers a grouping
    /// question that is not being asked.
    static func layout(
        _ items: [Item],
        area: CGSize,
        options: Options = Options(),
        stacking: Bool = true
    ) -> Layout {
        let partitions = split(items)

        // Both searches below are over monotone choices, so they bisect: the same answer as trying
        // every option, in a handful of passes rather than dozens.
        let singles = partitions.map { $0.items.map { [$0] } }
        let diameters = Int(options.maxDiameter - options.minDiameter) + 1
        let widest = firstFit(diameters) {
            attempt(
                diameter: options.maxDiameter - CGFloat($0),
                groups: singles,
                partitions: partitions,
                area: area,
                options: options
            ).fits
        }

        if widest < diameters {
            return attempt(
                diameter: options.maxDiameter - CGFloat(widest),
                groups: singles,
                partitions: partitions,
                area: area,
                options: options
            )
        }

        guard stacking else {
            return attempt(
                diameter: options.minDiameter,
                groups: singles,
                partitions: partitions,
                area: area,
                options: options
            )
        }

        return stacked(partitions, area: area, options: options)
    }
}

// MARK: - Packing

private extension CoinageGridLayout {
    struct Partition {
        let partition: CoinageStripLayout.Partition
        var items: [Item]
    }

    struct Run {
        var items: [Item]
        var level: Int
    }

    static func split(_ items: [Item]) -> [Partition] {
        items.reduce(into: [Partition]()) { partitions, item in
            if partitions.last?.partition == item.partition {
                partitions[partitions.count - 1].items.append(item)
            } else {
                partitions.append(Partition(partition: item.partition, items: [item]))
            }
        }
    }

    /// Smallest index in `0 ..< count` that fits, given fitting is monotone; `count` if none does.
    static func firstFit(_ count: Int, _ fits: (Int) -> Bool) -> Int {
        var low = 0
        var high = count

        while low < high {
            let mid = (low + high) / 2

            if fits(mid) {
                high = mid
            } else {
                low = mid + 1
            }
        }

        return low
    }

    static func attempt(
        diameter: CGFloat,
        groups: [[[Item]]],
        partitions: [Partition],
        area: CGSize,
        options: Options
    ) -> Layout {
        let pitch = diameter + options.gap
        let columns = max(1, Int((area.width - pitch / 2 + options.gap) / pitch))
        let rowHeight = pitch * 3.0.squareRoot() / 2

        var cells: [Cell] = []
        var blocks: [Block] = []
        var top: CGFloat = 0

        for (index, partition) in partitions.enumerated() {
            let units = groups[index]

            if index > 0 { top += options.blockGap }

            blocks.append(
                Block(partition: partition.partition, top: top, count: partition.items.count)
            )
            top += options.header

            let rows = Int(ceil(Double(units.count) / Double(columns)))

            for (position, unit) in units.enumerated() {
                let row = position / columns
                let column = position % columns

                cells.append(
                    Cell(
                        ids: unit.map(\.id),
                        count: unit.count,
                        centre: CGPoint(
                            x: diameter / 2 + CGFloat(column) * pitch
                                + CGFloat(row % 2) * (pitch / 2),
                            y: top + diameter / 2 + CGFloat(row) * rowHeight
                        )
                    )
                )
            }

            top += rows > 0 ? CGFloat(rows - 1) * rowHeight + diameter : 0
        }

        return Layout(
            diameter: diameter,
            pitch: pitch,
            columns: columns,
            cells: cells,
            blocks: blocks,
            height: top,
            fits: top <= area.height
        )
    }

    /// One rule for all of them: every run of at least `k` alike coins becomes a pile, `k` as large
    /// as still fits. Only runs worth a pile become one, so the grid keeps most coins loose and a
    /// handful of clear piles rather than a count on every other cell.
    static func stacked(_ partitions: [Partition], area: CGSize, options: Options) -> Layout {
        let grouped = partitions.map { runs(of: $0.items) }
        let lengths = Set(
            grouped.flatMap { $0 }.filter { $0.items.count > 1 }.map(\.items.count)
        ).sorted(by: >)

        func stackAt(_ threshold: Int) -> [[[Item]]] {
            grouped.map { list in
                list.flatMap { run in
                    run.items.count >= threshold ? [run.items] : run.items.map { [$0] }
                }
            }
        }

        let chosen = firstFit(lengths.count) {
            attempt(
                diameter: options.minDiameter,
                groups: stackAt(lengths[$0]),
                partitions: partitions,
                area: area,
                options: options
            ).fits
        }

        let groups = chosen < lengths.count
            ? stackAt(lengths[chosen])
            : grouped.map { $0.map(\.items) }

        return attempt(
            diameter: options.minDiameter,
            groups: groups,
            partitions: partitions,
            area: area,
            options: options
        )
    }

    /// Consecutive coins alike in value, state and how hidden. Ready coins are alike whether or not
    /// they are still in a ring; clearing keeps recycling apart from will-recycle.
    static func runs(of items: [Item]) -> [Run] {
        func kind(_ item: Item) -> String {
            item.partition == .ready ? "ready" : item.status
        }

        return items.reduce(into: [Run]()) { runs, item in
            if let head = runs.last?.items.first,
               head.exponent == item.exponent,
               kind(head) == kind(item),
               hiddenBand(level: head.level) == hiddenBand(level: item.level) {
                runs[runs.count - 1].items.append(item)
                runs[runs.count - 1].level = min(runs[runs.count - 1].level, item.level)
            } else {
                runs.append(Run(items: [item], level: item.level))
            }
        }
    }
}
