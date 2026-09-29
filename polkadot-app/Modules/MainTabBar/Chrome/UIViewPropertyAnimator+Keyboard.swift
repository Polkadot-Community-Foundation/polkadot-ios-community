import UIKit

extension UIViewPropertyAnimator {
    /// Mirrors a keyboard notification's duration and curve, so chrome driven by the keys moves
    /// with them instead of snapping ahead of them.
    static func keyboardMatching(_ notification: NSNotification) -> UIViewPropertyAnimator {
        let userInfo = notification.userInfo
        let duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.3
        let curveRawValue = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 0
        let curve = UIView.AnimationCurve(rawValue: curveRawValue) ?? .linear

        return UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UICubicTimingParameters(animationCurve: curve)
        )
    }
}
