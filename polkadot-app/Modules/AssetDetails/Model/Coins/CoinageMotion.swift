import CoreGraphics
import Foundation

/// A critically damped spring, exact for any time step.
///
/// Every channel of every coin runs one of these, so an arrangement change only moves targets and a
/// tap mid-flight simply re-aims. Ported from `src/layout/springs.js`.
struct CoinageSpring: Equatable {
    var value: CGFloat
    var velocity: CGFloat = 0

    init(value: CGFloat = 0, velocity: CGFloat = 0) {
        self.value = value
        self.velocity = velocity
    }

    /// Below this a channel counts as at rest, and a frame with nothing above it is not drawn.
    static let epsilon: CGFloat = 0.0005

    static func step(
        value: CGFloat,
        velocity: CGFloat,
        target: CGFloat,
        step seconds: CGFloat,
        omega: CGFloat
    ) -> (value: CGFloat, velocity: CGFloat) {
        let offset = value - target
        let decay = exp(-omega * seconds)
        let travel = (velocity + omega * offset) * seconds

        return (target + (offset + travel) * decay, (velocity - omega * travel) * decay)
    }

    mutating func step(toward target: CGFloat, seconds: CGFloat, omega: CGFloat) {
        let stepped = Self.step(
            value: value,
            velocity: velocity,
            target: target,
            step: seconds,
            omega: omega
        )
        value = stepped.value
        velocity = stepped.velocity
    }

    func isSettled(at target: CGFloat) -> Bool {
        abs(value - target) < Self.epsilon && abs(velocity) < Self.epsilon
    }

    /// How fast each channel chases its target. Position moves fastest, wear slowest: a coin
    /// changing how hidden it is should ease between levels rather than snap.
    enum Omega {
        static let position: CGFloat = 13
        static let rotation: CGFloat = 9
        static let thickness: CGFloat = 10
        static let recede: CGFloat = 8
        static let luster: CGFloat = 7
        static let wear: CGFloat = 2.2
    }

    /// Strip and grid moves stagger their starts across this long, in display order, so the field
    /// unfolds rather than jumping as one block.
    static let stagger: CGFloat = 0.18
}

/// Which mesh a coin is drawn with, coarsest last.
///
/// Picked from what the coin actually covers in device pixels rather than from its arrangement, so
/// a coin turned nearly edge-on drops to a sliver however large its face would have been.
enum CoinageLevelOfDetail: Int, CaseIterable {
    case high = 0
    case mid = 1
    case low = 2
    case sliver = 3

    static func forCoin(heightPixels: CGFloat, visibleWidthPixels: CGFloat) -> CoinageLevelOfDetail {
        if visibleWidthPixels < 3.5 {
            .sliver
        } else if heightPixels < 34 || visibleWidthPixels < 7 {
            .low
        } else if heightPixels < 110 {
            .mid
        } else {
            .high
        }
    }

    /// What a coin covers horizontally, which is the face and the edge in whatever mix its turn
    /// gives.
    static func visibleWidth(
        height: CGFloat,
        faceWidth: CGFloat,
        thickness: CGFloat,
        turn: CGFloat
    ) -> CGFloat {
        height * (abs(cos(turn)) * faceWidth + abs(sin(turn)) * thickness)
    }

    /// Motion hides mesh detail, so coins still travelling never take the finest one. Without the
    /// cap a thousand-coin move between the strip and the grid drew millions of triangles a frame.
    func capped(inFlight: Bool, movingCoins: Int) -> CoinageLevelOfDetail {
        guard inFlight else { return self }

        let ceiling: CoinageLevelOfDetail = movingCoins > 300 ? .low : .mid

        return rawValue > ceiling.rawValue ? self : ceiling
    }
}
