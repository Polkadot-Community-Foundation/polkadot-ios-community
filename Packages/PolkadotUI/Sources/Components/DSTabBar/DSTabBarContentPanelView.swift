import UIKit
import DesignSystem

/// Hosts either a content configuration or a child controller's view; both size themselves and
/// are measured the same way. A controller cannot be wrapped in a `UIContentView` without
/// losing its appearance callbacks, so the two modes exist side by side and are exclusive.
public final class DSTabBarContentPanelView: UIView {
    public private(set) var isOpen = false

    private let container = UIView()
    private var contentView: (UIView & UIContentView)?
    private var contentReuseIdentifier: String?
    private var hostedView: UIView?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        container.clipsToBounds = true
        container.alpha = 0
        addSubview(container)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setConfiguration(_ configuration: (any HashableContentConfiguration)?) {
        guard let configuration else {
            clearContentView()
            return
        }

        clearHostedView()

        if let contentView,
           contentReuseIdentifier == configuration.defaultReuseIdentifier {
            contentView.configuration = configuration
            contentView.invalidateIntrinsicContentSize()
            return
        }

        contentView?.removeFromSuperview()

        let newContentView = configuration.makeContentView()
        container.addSubview(newContentView)

        contentView = newContentView
        contentReuseIdentifier = configuration.defaultReuseIdentifier
        setNeedsLayout()
    }

    /// The hosted view's own constraints decide the panel height. The bottom pin yields so a view
    /// with a required aspect constraint keeps its shape while the container animates to fit it.
    public func setHostedView(_ view: UIView?) {
        guard let view else {
            clearHostedView()
            return
        }

        clearContentView()

        guard hostedView !== view else {
            setNeedsLayout()
            return
        }

        hostedView?.removeFromSuperview()
        hostedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        let bottom = view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        bottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottom
        ])

        setNeedsLayout()
    }

    public func preferredHeight(availableHeight: CGFloat) -> CGFloat {
        let candidate: UIView? = hostedView ?? contentView

        guard let measuredView = candidate, bounds.width > 0 else {
            return DSTabBarMetrics.capsuleHeight
        }

        let measuredSize = measuredView.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        return DSTabBarPanelLayout.panelHeight(
            contentHeight: measuredSize.height,
            availableHeight: availableHeight
        )
    }

    /// Adds the panel's open/close animations to `animator` so they stay in lockstep with the
    /// container resize the caller drives; applies them immediately when `animator` is nil.
    public func setOpen(_ open: Bool, animator: UIViewPropertyAnimator?) {
        guard open != isOpen else {
            return
        }
        isOpen = open

        let apply = { [self] in
            container.alpha = open ? 1 : 0
        }

        guard let animator else {
            apply()
            return
        }

        animator.addAnimations(apply)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        container.frame = bounds
        contentView?.frame = container.bounds
    }
}

private extension DSTabBarContentPanelView {
    func clearContentView() {
        contentView?.removeFromSuperview()
        contentView = nil
        contentReuseIdentifier = nil
    }

    func clearHostedView() {
        hostedView?.removeFromSuperview()
        hostedView = nil
    }
}
