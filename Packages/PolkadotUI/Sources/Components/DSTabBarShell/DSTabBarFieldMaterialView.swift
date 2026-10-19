import UIKit

/// The brief's search field material: white 6 % fill, a white 18 % line along the top and a 1 pt white 8 % outline.
final class DSTabBarFieldMaterialView: UIView {
    private let cornerRadius: CGFloat
    private let topLineLayer = CAShapeLayer()
    private let topLineMask = CAGradientLayer()

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTopLine()
    }
}

private extension DSTabBarFieldMaterialView {
    func setupLayers() {
        isUserInteractionEnabled = false
        backgroundColor = UIColor(DSTabBarStyle.Palette.fieldFill)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(DSTabBarStyle.Palette.fieldOutline).cgColor

        topLineLayer.fillColor = UIColor.clear.cgColor
        topLineLayer.strokeColor = UIColor(DSTabBarStyle.Palette.fieldTopLine).cgColor
        topLineLayer.lineWidth = 1

        topLineMask.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        topLineMask.locations = [0, 0.3]
        topLineMask.startPoint = CGPoint(x: 0.5, y: 0)
        topLineMask.endPoint = CGPoint(x: 0.5, y: 1)
        topLineLayer.mask = topLineMask

        layer.addSublayer(topLineLayer)
    }

    func updateTopLine() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topLineLayer.frame = bounds
        topLineMask.frame = bounds
        topLineLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: max(0, cornerRadius - 0.5)
        ).cgPath
        CATransaction.commit()
    }
}
