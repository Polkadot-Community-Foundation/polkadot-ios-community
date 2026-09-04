import Testing
import CoreGraphics
@testable import PolkadotUI

@Suite("DSTabBarRow")
struct DSTabBarRowTests {
    private let row = DSTabBarRow(width: 400, itemCount: 5)

    @Test("Every item gets the same width")
    func uniformItemWidths() {
        let widths = (0 ..< row.itemCount).map { row.itemFrame(at: $0).width }

        #expect(widths.allSatisfy { $0 == widths[0] })
        #expect(widths[0] > 0)
    }

    @Test("Item frames advance left to right")
    func monotonicItemFrames() {
        let origins = (0 ..< row.itemCount).map { row.itemFrame(at: $0).minX }

        #expect(zip(origins, origins.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Adding an item narrows every item")
    func widthScalesWithItemCount() {
        let wider = DSTabBarRow(width: 400, itemCount: 5).itemFrame(at: 0).width
        let narrower = DSTabBarRow(width: 400, itemCount: 6).itemFrame(at: 0).width

        #expect(narrower < wider)
    }

    @Test("Nearest index snaps to the candidate whose centre is closest")
    func nearestIndexSnapsToCandidate() {
        let candidates = [0, 1, 3, 4]

        for index in candidates {
            let centre = row.itemFrame(at: index).midX
            #expect(row.nearestItemIndex(toX: centre, restrictedTo: candidates) == index)
        }
    }

    @Test("Nearest index never returns an excluded index")
    func nearestIndexSkipsExcluded() {
        let candidates = [0, 1, 3, 4]
        let excludedCentre = row.itemFrame(at: 2).midX

        let resolved = row.nearestItemIndex(toX: excludedCentre, restrictedTo: candidates)

        #expect(resolved == 1 || resolved == 3)
    }

    @Test("Nearest index is nil without candidates")
    func nearestIndexWithoutCandidates() {
        #expect(row.nearestItemIndex(toX: 100, restrictedTo: []) == nil)
    }
}
