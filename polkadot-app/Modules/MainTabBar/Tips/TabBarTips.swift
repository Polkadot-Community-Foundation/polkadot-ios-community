import TipKit

enum TabBarTips {
    /// Transient: resets every launch, so no tip fires before the bar resolves its visibility.
    @Parameter(.transient)
    static var isBarShownAtRoot: Bool = false

    /// The tip chain: the top status strip first, then the scan action. Single source of truth:
    /// the chrome builds its sequence from this, and Debug Settings resets eligibility across it.
    @MainActor
    static let steps: [TabBarTipStep] = [
        TabBarTipStep(tip: ScanActionTip(), anchor: .barItem(.action(.scan))),
        TabBarTipStep(tip: ChainStatusStripTip(), anchor: .statusStrip)
    ]
}
