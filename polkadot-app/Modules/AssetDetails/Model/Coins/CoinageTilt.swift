import CoreMotion
import Foundation

/// Turns the studio with the phone, so the light behaves as though it were fixed in the room.
///
/// The environment the coins are lit against is defined around the coin's own space, so with the
/// studio held still the highlight sits in the same place however the phone is held. Feeding the
/// device's own tilt back in turns the studio the other way, and a coin catches the light as you
/// tilt it, the way a real one does.
///
/// Read from gravity rather than from the attitude's Euler angles. Roll and pitch are degenerate
/// when a phone is held upright — the orientation the coins are normally looked at in — which made
/// the light jump about near vertical and answer a tilt one way but not the other. Gravity is well
/// behaved everywhere except flat on a table, where the screen plane has no "down" to speak of and
/// the sideways angle is simply left where it was.
///
/// Device motion needs no permission prompt: `CMMotionManager` reads the accelerometer and gyro
/// directly. Only `CMMotionActivityManager`, which classifies walking and driving, requires
/// `NSMotionUsageDescription` and asks the user. This reads attitude only.
final class CoinageTilt {
    struct Angles: Equatable {
        /// Swings the light sideways, from tilting the phone left or right.
        var yaw: CGFloat = 0
        /// Lifts the light over the coin or drops it below, from leaning the phone back or forward.
        var pitch: CGFloat = 0
    }

    /// How far the studio turns at the ends of the travel. A whole rotation would swing the
    /// highlight right around the coin, which reads as a spinning lamp rather than a coin in a hand.
    static let travel: CGFloat = 0.9

    /// The tilt either way that reaches the ends of the travel. Deliberately short of a right
    /// angle: nobody turns a phone ninety degrees to look at it, and the whole range should be
    /// within a normal movement of the wrist.
    static let range: CGFloat = .pi / 4

    /// How long it takes for however the phone is being held to become the new neutral.
    ///
    /// Zero offset is where the studio sits as it was calibrated: square to the screen, which is
    /// where the coins have most contrast. Any fixed idea of how a phone is held is wrong for
    /// somebody — lying down, propped on a desk, held low — and leaves them permanently off that
    /// angle with the light stuck in a poor place. Letting neutral follow the last few seconds
    /// makes the light answer how the phone is being *moved* and settle back to its best angle
    /// whenever it is held still, whatever the posture.
    static let recentre: TimeInterval = 5

    /// Below this share of gravity in the screen plane the phone is flat enough that left and right
    /// stop meaning anything, and the sideways angle holds still rather than chasing noise.
    static let flatThreshold = 0.2

    /// Chases the device rather than tracking it exactly: raw attitude is noisy enough to make a
    /// specular highlight shimmer while the phone is held still.
    static let smoothing: CGFloat = 8

    private static let epsilon: CGFloat = 0.0008
    private static let interval: TimeInterval = 1.0 / 60

    private let motion = CMMotionManager()
    private var neutral: Neutral?
    private var target = Angles()

    private(set) var angles = Angles()

    /// Called when the phone has moved enough that the studio needs to catch up. The view pauses
    /// itself whenever nothing is moving, so without a push from outside it would never look at the
    /// attitude again and the light would stay where the field last settled.
    var onMove: (() -> Void)?

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }

        motion.deviceMotionUpdateInterval = Self.interval
        motion.startDeviceMotionUpdates(to: .main) { [weak self] update, _ in
            guard let self, let gravity = update?.gravity else { return }

            absorb(Pose(gravity: gravity), after: Self.interval)
        }
    }

    func stop() {
        guard motion.isDeviceMotionActive else { return }

        motion.stopDeviceMotionUpdates()
        neutral = nil
        onMove = nil
    }

    /// Eases toward the latest tilt. Returns whether the studio is still catching up, so a field at
    /// rest under a still hand goes back to sleep.
    @discardableResult
    func advance(by seconds: CGFloat) -> Bool {
        let reached = abs(target.yaw - angles.yaw) <= Self.epsilon
            && abs(target.pitch - angles.pitch) <= Self.epsilon

        guard !reached else { return false }

        let step = min(seconds * Self.smoothing, 1)
        angles.yaw += (target.yaw - angles.yaw) * step
        angles.pitch += (target.pitch - angles.pitch) * step

        return true
    }

    /// Folds one reading into the neutral and works out where the light should sit against it.
    ///
    /// The first reading becomes the neutral outright, so the light starts square rather than
    /// drifting in from wherever the phone happened to be picked up.
    func absorb(_ pose: Pose, after seconds: TimeInterval) {
        var settled = neutral ?? Neutral(pose: pose)
        settled.absorb(pose, blend: neutral == nil ? 1 : min(seconds / Self.recentre, 1))
        neutral = settled

        target = Angles(
            yaw: pose.isFlat ? target.yaw : Self.scaled(settled.sidewaysOffset(of: pose)),
            pitch: Self.scaled(pose.lean - settled.lean)
        )

        if abs(target.yaw - angles.yaw) > Self.epsilon || abs(target.pitch - angles.pitch) > Self.epsilon {
            onMove?()
        }
    }

    static func scaled(_ angle: CGFloat) -> CGFloat {
        min(max(angle, -range), range) / range * travel
    }
}

// MARK: - Readings

extension CoinageTilt {
    /// One reading, as the two angles that matter rather than as a raw vector.
    struct Pose: Equatable {
        /// Which way is down in the screen plane: what a hand does tilting a phone to catch light.
        let sideways: CGFloat
        /// How far the screen is leaned away from vertical.
        let lean: CGFloat
        /// Flat enough that the screen plane has no down worth speaking of.
        let isFlat: Bool

        init(gravity: CMAcceleration) {
            let planar = (gravity.x * gravity.x + gravity.y * gravity.y).squareRoot()
            sideways = atan2(CGFloat(gravity.x), CGFloat(-gravity.y))
            lean = CGFloat(asin(min(max(-gravity.z, -1), 1)))
            isFlat = planar <= CoinageTilt.flatThreshold
        }
    }

    /// However the phone has been held lately, which is what the light treats as square.
    ///
    /// Sideways is averaged as a direction rather than as a number: it comes from `atan2` and wraps
    /// at half a turn, so averaging the angle itself would put a phone held near that wrap at the
    /// opposite bearing.
    struct Neutral: Equatable {
        private(set) var sidewaysX: CGFloat
        private(set) var sidewaysY: CGFloat
        private(set) var lean: CGFloat

        init(pose: Pose) {
            sidewaysX = cos(pose.sideways)
            sidewaysY = sin(pose.sideways)
            lean = pose.lean
        }

        var sideways: CGFloat { atan2(sidewaysY, sidewaysX) }

        mutating func absorb(_ pose: Pose, blend: CGFloat) {
            // A phone lying flat has no bearing to contribute, so only the lean is folded in.
            if !pose.isFlat {
                sidewaysX += (cos(pose.sideways) - sidewaysX) * blend
                sidewaysY += (sin(pose.sideways) - sidewaysY) * blend
            }

            lean += (pose.lean - lean) * blend
        }

        /// How far the phone is turned from neutral, by the shorter way round.
        func sidewaysOffset(of pose: Pose) -> CGFloat {
            let difference = pose.sideways - sideways

            return atan2(sin(difference), cos(difference))
        }
    }
}
