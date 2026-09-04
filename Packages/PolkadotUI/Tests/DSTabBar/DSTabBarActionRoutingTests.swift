import Testing
import UIKit
@testable import PolkadotUI

@Suite("DSTabBarView action routing")
@MainActor
struct DSTabBarActionRoutingTests {
    // chat, wallet, scan (action), settings, more (action)
    private let actionIndices = [2, 4]
    private let tabIndices = [0, 1, 3]

    private let capsuleWidth: CGFloat = 400

    private var row: DSTabBarRow {
        DSTabBarRow(
            width: DSTabBarGeometry.rowWidth(capsuleWidth: capsuleWidth),
            itemCount: 5
        )
    }

    @Test("An x inside an action frame resolves to that action")
    func pressInsideActionResolvesToAction() {
        let barView = makeBarView()

        for index in actionIndices {
            #expect(barView.resolvedTarget(atX: row.itemFrame(at: index).midX) == .action(index))
        }
    }

    @Test("An x over a tab resolves to that tab")
    func pressOverTabResolvesToTab() {
        let barView = makeBarView()

        for index in tabIndices {
            #expect(barView.resolvedTarget(atX: row.itemFrame(at: index).midX) == .tab(index))
        }
    }

    @Test("An x outside every item still resolves to the nearest tab")
    func pressOutsideItemsResolvesToNearestTab() {
        let barView = makeBarView()

        #expect(barView.resolvedTarget(atX: -100) == .tab(0))
        #expect(barView.resolvedTarget(atX: 10_000) == .tab(3))
    }

    @Test("An empty bar resolves to nothing")
    func emptyBarResolvesToNil() {
        let barView = DSTabBarView(frame: CGRect(x: 0, y: 0, width: capsuleWidth, height: 62))

        #expect(barView.resolvedTarget(atX: 100) == nil)
    }
}

private extension DSTabBarActionRoutingTests {
    func makeBarView() -> DSTabBarView {
        let barView = DSTabBarView(frame: CGRect(x: 0, y: 0, width: capsuleWidth, height: 62))
        barView.items = [
            makeItem(role: .tab),
            makeItem(role: .tab),
            makeItem(role: .action),
            makeItem(role: .tab),
            makeItem(role: .action)
        ]
        barView.layoutIfNeeded()
        return barView
    }

    func makeItem(role: DSTabBarItem.Role) -> DSTabBarItem {
        DSTabBarItem(
            icon: UIImage(),
            title: nil,
            role: role,
            accessibilityLabel: "item"
        )
    }
}
