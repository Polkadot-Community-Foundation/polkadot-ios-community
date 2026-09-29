import CoreMotion
import Foundation

/// Turns the studio with the phone, so the light behaves as though it were fixed in the room.
///
/// The environment the coins are lit against is defined around the coin's own space, so with a
/// fixed yaw the highlight sits in the same place however the phone is held. Feeding the device's
/// own yaw back in turns the studio the other way, and a coin catches the light as you tilt it, the
/// way a real one does.
///
/// Device motion needs no permission prompt: `CMMotionManager` reads the accelerometer and gyro
/// directly. Only `CMMotionActivityManager`, which classifies walking and driving, requires
/// `NSMotionUsageDescription` and asks the user. This reads attitude only.
final class CoinageTilt {
    /// How far the studio turns between the phone lying flat and being held upright. A whole
    /// rotation would swing the highlight right around the coin, which reads as a spinning lamp
    /// rather than a coin being tilted.
    static let travel: CGFloat = 0.9

    /// Chases the device rather than tracking it exactly: raw attitude is noisy enough to make a
    /// specular highlight shimmer while the phone is still.
    static let smoothing: CGFloat = 8

    private let motion = CMMotionManager()
    private var target: CGFloat = 0

    private(set) var yaw: CGFloat = 0

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }

        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates()
    }

    func stop() {
        guard motion.isDeviceMotionActive else { return }

        motion.stopDeviceMotionUpdates()
    }

    /// Reads the latest attitude and eases toward it. Returns whether the studio is still moving,
    /// so a settled field is not woken for a hand that is holding still.
    @discardableResult
    func advance(by seconds: CGFloat) -> Bool {
        guard let attitude = motion.deviceMotion?.attitude else { return false }

        // Roll is the phone turning about the axis running out of the screen, which is the one that
        // should swing the light sideways. Pitch leans it away, which the studio already handles.
        target = CGFloat(attitude.roll).clamped(to: -.pi / 2 ... .pi / 2) / (.pi / 2) * Self.travel

        let eased = yaw + (target - yaw) * min(seconds * Self.smoothing, 1)
        let moved = abs(eased - yaw) > 0.0002
        yaw = eased

        return moved
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
