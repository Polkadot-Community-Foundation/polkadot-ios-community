import UIKit
import DesignSystem
import PolkadotUI
import SnapKit

final class TabBarChromeSurfaceView: UIView {
    private let glassContainer = DSGlassContainerView(
        shape: .rounded(32),
        tint: nil
    )
    private let tabsPanelView = DSTabBarTabsPanelView()
    private let contentPanelView = DSTabBarContentPanelView()

    private weak var barView: DSTabBarView?
    private var glassContainerHeightConstraint: Constraint?
    private var appliedGlassContainerHeight: CGFloat = 0
    private var glassContainerKeyboardConstraint: Constraint?
    private var barKeyboardConstraint: Constraint?
    private var isPanelTrackingKeyboard = false
    private var isContentFilling = false
    private var isBarVisible = true
    private var keyboardAvoidanceAnimator: UIViewPropertyAnimator?
    private var isBarSettling = false

    /// At rest the chrome only clears the home indicator gap, and it keeps that same gap once it
    /// rides above the keys. While the chrome's own search is focused it sinks instead, by half a
    /// capsule, so the capsule's lower half hides behind the keys.
    private static let restingBottomOffset = -DSTabBarView.bottomGap
    private static let sunkenBottomOffset = DSTabBarView.capsuleHeight / 2

    var availablePanelHeight: CGFloat {
        let occupiedHeight: CGFloat =
            if isPanelTrackingKeyboard {
                bounds.height - keyboardLayoutGuide.layoutFrame.minY - Self.sunkenBottomOffset
            } else {
                DSTabBarView.preferredHeight()
            }

        return bounds.height - topInset - occupiedHeight
    }

    /// The chain-status strip reaches the chrome as an additional top safe-area inset. A filling
    /// panel passes under it and stops at the status bar; every other state keeps clear of it.
    private var topInset: CGFloat {
        guard isContentFilling, let windowInset = window?.safeAreaInsets.top else {
            return safeAreaInsets.top
        }
        return windowInset
    }

    var onChipTapped: ((UUID) -> Void)?
    var onChipCloseRequested: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Without the bottom safe area the dismissed guide rests on the view's bottom edge,
        // leaving the keyboard inequality slack instead of lifting the chrome by the home indicator.
        keyboardLayoutGuide.usesBottomSafeArea = false

        installGlassContainer()
        installTabsPanel()
        installContentPanel()
        observeKeyboard()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    func addBar(_ bar: DSTabBarView) {
        addSubview(bar)
        barView = bar

        bar.snp.makeConstraints { make in
            make.leading.trailing.equalTo(glassContainer.contentView)
            make.height.equalTo(DSTabBarView.capsuleHeight)
            barKeyboardConstraint = pinBottomAvoidingKeyboard(make)
        }
    }

    func setPanelsOpen(_ kind: TabBarPanelKind?, animator: UIViewPropertyAnimator?) {
        tabsPanelView.setOpen(kind == .spaTabs, animator: animator)
        contentPanelView.setOpen(kind?.contentAction != nil, animator: animator)
    }

    @discardableResult
    func updateHeight(for kind: TabBarPanelKind?, animator: UIViewPropertyAnimator?) -> Bool {
        let containerHeight: CGFloat =
            switch kind {
            case .spaTabs:
                tabsPanelView.preferredHeight(availableHeight: availablePanelHeight)
            case .content:
                // While a search is active the content fills the space above the keys or the
                // tab bar instead of fitting its rows.
                if isContentFilling {
                    max(0, availablePanelHeight)
                } else {
                    contentPanelView.preferredHeight(availableHeight: availablePanelHeight)
                }
            case nil:
                DSTabBarView.capsuleHeight
            }

        guard containerHeight != appliedGlassContainerHeight else {
            return false
        }

        appliedGlassContainerHeight = containerHeight
        glassContainerHeightConstraint?.update(offset: containerHeight)

        animator?.addAnimations { [weak self] in
            self?.layoutIfNeeded()
        }

        return true
    }

    func setChips(_ chips: [DSTabBarChip], selected: UUID?, closeActionTitle: String) {
        tabsPanelView.setChips(chips, selected: selected)
        tabsPanelView.closeActionTitle = closeActionTitle
    }

    func setContentConfiguration(_ configuration: (any HashableContentConfiguration)?) {
        contentPanelView.setConfiguration(configuration)
    }

    func setContentHostedView(_ view: UIView?) {
        contentPanelView.setHostedView(view)
    }

    func setPanelTracksKeyboard(_ tracking: Bool) {
        guard tracking != isPanelTrackingKeyboard else {
            return
        }

        isPanelTrackingKeyboard = tracking

        let offset = tracking ? Self.sunkenBottomOffset : Self.restingBottomOffset
        glassContainerKeyboardConstraint?.update(offset: offset)
        barKeyboardConstraint?.update(offset: offset)
        barView?.setKeyboardShadowVisible(tracking)

        guard tracking else { return }
        // The panel tracks only while a keyboard is up. Arming here too keeps the caller's
        // animator correct whichever of the two keyboard observers ran first.
        setKeyboardAvoidance(isBarVisible)
    }

    /// A hidden bar is only translated aside, not unloaded, so it still answers to the keyboard.
    /// Only ever disarms: a returning bar must not arm, because a pop restores it at the start of
    /// the transition while the keyboard is still on screen. The drop back to rest joins the fold
    /// animator, so it does not snap while the bar slides aside.
    func setBarVisible(_ visible: Bool, animator: UIViewPropertyAnimator?) {
        isBarVisible = visible

        guard !visible else {
            settle(with: animator)
            return
        }

        setPanelTracksKeyboard(false)
        setKeyboardAvoidance(false)

        animator?.addAnimations { [weak self] in
            self?.layoutIfNeeded()
        }
    }

    /// While a search is active the content panel fills the available height instead of fitting its rows.
    func setContentFillsAvailableHeight(_ fills: Bool) {
        isContentFilling = fills
    }
}

// MARK: - Keyboard

private extension TabBarChromeSurfaceView {
    func observeKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    /// iOS 17 replays a keyboard show for the screen being torn down, after the bar is already
    /// back on screen, so the bar would rise to it and drop again. Keyboard traffic is ignored
    /// until the reveal has settled.
    @objc
    func handleKeyboardWillShow(_ notification: NSNotification) {
        guard !isBarSettling else {
            return
        }

        setKeyboardAvoidance(isBarVisible, matching: notification)
    }

    @objc
    func handleKeyboardWillHide(_ notification: NSNotification) {
        setKeyboardAvoidance(false, matching: notification)
    }

    /// The animator is the one revealing the bar; the reveal is over when it finishes.
    func settle(with animator: UIViewPropertyAnimator?) {
        isBarSettling = animator != nil

        animator?.addCompletion { [weak self] _ in
            self?.isBarSettling = false
        }
    }

    func setKeyboardAvoidance(_ active: Bool, matching notification: NSNotification) {
        setKeyboardAvoidance(active)

        let animator = UIViewPropertyAnimator.keyboardMatching(notification)
        animator.addAnimations { [weak self] in
            self?.layoutIfNeeded()
        }
        animator.addCompletion { [weak self] _ in
            self?.keyboardAvoidanceAnimator = nil
        }
        keyboardAvoidanceAnimator = animator
        animator.startAnimation()
    }

    /// Any animator of ours is dropped first: whoever changes the arming owns the move from here.
    func setKeyboardAvoidance(_ active: Bool) {
        keyboardAvoidanceAnimator?.cancelInPlace()

        if active {
            glassContainerKeyboardConstraint?.activate()
            barKeyboardConstraint?.activate()
        } else {
            glassContainerKeyboardConstraint?.deactivate()
            barKeyboardConstraint?.deactivate()
        }
    }
}

// MARK: - Layout

private extension TabBarChromeSurfaceView {
    /// Pins a view to the chrome's bottom at rest, only preferred, so the required keyboard
    /// inequality wins once the keys cover that position. Returns the inequality: its offset picks
    /// the riding height, and it stays inactive until a keyboard is up with the bar on screen.
    func pinBottomAvoidingKeyboard(_ make: ConstraintMaker) -> Constraint {
        make.bottom.equalToSuperview().offset(Self.restingBottomOffset).priority(.high)

        let keyboardConstraint = make.bottom.lessThanOrEqualTo(keyboardLayoutGuide.snp.top)
            .offset(Self.restingBottomOffset).constraint
        keyboardConstraint.deactivate()

        return keyboardConstraint
    }

    func installGlassContainer() {
        insertSubview(glassContainer, at: 0)
        glassContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(DSTabBarView.maxWidth)
            make.width.equalToSuperview().offset(-DSTabBarView.horizontalMargin * 2).priority(.high)
            glassContainerKeyboardConstraint = pinBottomAvoidingKeyboard(make)
            glassContainerHeightConstraint = make.height.equalTo(DSTabBarView.capsuleHeight).constraint
        }
    }

    func installTabsPanel() {
        installPanel(tabsPanelView)

        tabsPanelView.onChipTapped = { [weak self] id in self?.onChipTapped?(id) }
        tabsPanelView.onChipCloseRequested = { [weak self] id in self?.onChipCloseRequested?(id) }
    }

    func installContentPanel() {
        installPanel(contentPanelView)
    }

    /// Both panels fill the glass above the capsule, which stays uncovered at the bottom,
    /// and always stop a capsule short of the glass bottom, at rest and over the keyboard alike.
    func installPanel(_ panel: UIView) {
        addSubview(panel)

        panel.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(glassContainer.contentView)
            make.bottom.equalTo(glassContainer.contentView)
                .offset(-DSTabBarView.capsuleHeight)
        }
    }
}
