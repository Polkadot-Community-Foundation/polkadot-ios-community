import Testing

@testable import polkadot_app

@Suite("TabBarSlotMap")
struct TabBarSlotMapTests {
    private let productSlots: [TabBarSlot] = [
        .tab(.chat), .tab(.wallet), .action(.scan), .tab(.browse), .tab(.settings), .action(.more)
    ]

    private let plainSlots: [TabBarSlot] = [
        .tab(.chat), .tab(.wallet), .action(.scan), .tab(.settings), .action(.more)
    ]

    @Test("Tab indices round-trip through item space")
    func roundTripsBothArms() {
        for slots in [productSlots, plainSlots] {
            let map = TabBarSlotMap(slots: slots)
            let tabCount = slots.compactMap(\.tab).count

            for tabIndex in 0 ..< tabCount {
                let itemIndex = map.itemIndex(forTabIndex: tabIndex)
                #expect(itemIndex != nil)
                #expect(itemIndex.flatMap { map.tabIndex(forItemIndex: $0) } == tabIndex)
            }
        }
    }

    @Test("Appending the SPA-tabs action leaves tab indices untouched")
    func spaTabsSlotDoesNotSkewTabs() {
        let withoutSPA = TabBarSlotMap(slots: productSlots)
        let withSPA = TabBarSlotMap(slots: productSlots + [.action(.spaTabs)])

        for tabIndex in 0 ..< 4 {
            #expect(withSPA.itemIndex(forTabIndex: tabIndex) == withoutSPA.itemIndex(forTabIndex: tabIndex))
        }
        #expect(withSPA.itemIndex(for: .spaTabs) == productSlots.count)
        #expect(withoutSPA.itemIndex(for: .spaTabs) == nil)
    }

    @Test("Action item indices resolve back to their action")
    func actionsResolveFromItemIndex() {
        let map = TabBarSlotMap(slots: plainSlots)

        #expect(map.action(forItemIndex: 2) == .scan)
        #expect(map.action(forItemIndex: 4) == .more)
        #expect(map.itemIndex(for: .scan) == 2)
        #expect(map.itemIndex(for: .more) == 4)
    }

    @Test("A tab item index carries no action")
    func tabsCarryNoAction() {
        let map = TabBarSlotMap(slots: plainSlots)

        #expect(map.action(forItemIndex: 0) == nil)
        #expect(map.tabIndex(forItemIndex: 2) == nil)
    }

    @Test("Out-of-range indices resolve to nil")
    func outOfRangeIsNil() {
        let map = TabBarSlotMap(slots: plainSlots)

        #expect(map.itemIndex(forTabIndex: 99) == nil)
        #expect(map.tabIndex(forItemIndex: 99) == nil)
        #expect(map.action(forItemIndex: 99) == nil)
    }
}
