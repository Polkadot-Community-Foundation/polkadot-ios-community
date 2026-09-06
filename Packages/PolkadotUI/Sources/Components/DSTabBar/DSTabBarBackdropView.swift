import UIKit

/// Full-bleed blur behind the tab bar chrome while a panel is open.
public final class DSTabBarBackdropView: UIView {
    private enum Constants {
        /// Fraction of the material to render; the full material reads far too heavy full-screen.
        static let blurIntensity: CGFloat = 0.10
        static let blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
    }

    public private(set) var isOpen = false

    private let effectView = UIVisualEffectView(effect: nil)

    /// Paused at `blurIntensity` so only a fraction of the material renders, which is the only
    /// way below the lightest system style. It must stay retained for that state to survive and
    /// must be stopped before dealloc, or UIKit traps on a running animator being released.
    private var intensityAnimator: UIViewPropertyAnimator?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        // The chrome's passthrough hit test returns early on any subview hit, which would
        // swallow the outside tap that closes the panel.
        isUserInteractionEnabled = false
        effectView.alpha = 0
        addSubview(effectView)

        applyIntensity()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        MainActor.assumeIsolated {
            invalidateIntensityAnimator()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The held blur is a fixed fraction, so only its visibility rides the panel animator.
    public func setOpen(_ open: Bool, animator: UIViewPropertyAnimator?) {
        guard open != isOpen else {
            return
        }
        isOpen = open

        if open {
            // The held interpolation is discarded whenever the chrome leaves the render tree,
            // leaving the model value behind — the full effect. Rebuilding on each open
            // restores the fraction without having to enumerate every trigger.
            applyIntensity()
        }

        let apply = { [self] in
            effectView.alpha = open ? 1 : 0
        }

        guard let animator else {
            apply()
            return
        }

        animator.addAnimations(apply)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        effectView.frame = bounds
    }
}

private extension DSTabBarBackdropView {
    func applyIntensity() {
        invalidateIntensityAnimator()

        // Backgrounding finishes the held animator and leaves the full effect applied. Without
        // clearing it the rebuilt animator interpolates from full to full and renders at 100%.
        effectView.effect = nil

        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effectView.effect = UIBlurEffect(style: Constants.blurStyle)
        }

        animator.startAnimation()
        animator.pauseAnimation()
        animator.fractionComplete = Constants.blurIntensity

        intensityAnimator = animator
    }

    func invalidateIntensityAnimator() {
        guard let animator = intensityAnimator else {
            return
        }

        if animator.state == .active {
            animator.stopAnimation(true)
        }
        intensityAnimator = nil
    }

    /// iOS discards a held animator's state across backgrounding, so it is rebuilt on return.
    @objc func handleDidBecomeActive() {
        applyIntensity()
    }
}
