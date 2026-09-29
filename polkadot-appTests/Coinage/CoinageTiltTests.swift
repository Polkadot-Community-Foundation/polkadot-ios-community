import CoreMotion
import Metal
import Testing

@testable import polkadot_app

/// The light angles cannot be tried in the simulator, which has no gyro, so the mapping from
/// gravity to where the studio sits is pinned here instead.
@Suite("Coin light tilt")
struct CoinageTiltTests {
    /// Gravity for a phone tilted `angle` radians to its right, held upright otherwise.
    private func sideways(_ angle: Double) -> CMAcceleration {
        CMAcceleration(x: sin(angle), y: -cos(angle), z: 0)
    }

    /// Gravity for a phone leaned `angle` radians back from vertical, screen toward the viewer.
    private func leaned(_ angle: Double) -> CMAcceleration {
        CMAcceleration(x: 0, y: -cos(angle), z: -sin(angle))
    }

    private func pose(_ gravity: CMAcceleration) -> CoinageTilt.Pose {
        CoinageTilt.Pose(gravity: gravity)
    }

    @Test("However the phone is first picked up, the light starts square")
    func firstReadingIsNeutral() {
        for held in [sideways(0), sideways(.pi / 5), leaned(1.1)] {
            let tilt = CoinageTilt()
            tilt.absorb(pose(held), after: 1.0 / 60)
            tilt.advance(by: 1)

            #expect(abs(tilt.angles.yaw) < 1e-6)
            #expect(abs(tilt.angles.pitch) < 1e-6)
        }
    }

    @Test("A tilt moves the light, and the same tilt either way moves it the same amount")
    func tiltsAreSymmetric() {
        func offset(_ angle: Double) -> CGFloat {
            let tilt = CoinageTilt()
            tilt.absorb(pose(sideways(0)), after: 1.0 / 60)
            tilt.absorb(pose(sideways(angle)), after: 1.0 / 60)
            tilt.advance(by: 1)

            return tilt.angles.yaw
        }

        #expect(offset(.pi / 8) > 0)
        #expect(abs(offset(.pi / 8) + offset(-.pi / 8)) < 1e-6)
    }

    @Test("Leaning back and forward move the light opposite ways")
    func leaningMovesTheLight() {
        func offset(_ angle: Double) -> CGFloat {
            let tilt = CoinageTilt()
            tilt.absorb(pose(leaned(0.5)), after: 1.0 / 60)
            tilt.absorb(pose(leaned(0.5 + angle)), after: 1.0 / 60)
            tilt.advance(by: 1)

            return tilt.angles.pitch
        }

        #expect(offset(0.3) > 0)
        #expect(offset(-0.3) < 0)
    }

    @Test("Held at any angle long enough, the light settles back to square")
    func neutralFollowsHowThePhoneIsHeld() {
        let tilt = CoinageTilt()
        tilt.absorb(pose(sideways(0)), after: 1.0 / 60)
        tilt.absorb(pose(sideways(.pi / 6)), after: 1.0 / 60)
        tilt.advance(by: 1)

        let atFirst = tilt.angles.yaw
        #expect(atFirst > 0.1)

        // Three times the window, so about a twentieth of the offset is left. Neutral chases
        // exponentially, it does not arrive.
        for _ in 0 ..< Int(CoinageTilt.recentre * 3 * 60) {
            tilt.absorb(pose(sideways(.pi / 6)), after: 1.0 / 60)
        }

        tilt.advance(by: 1)
        #expect(tilt.angles.yaw < atFirst / 10)
    }

    @Test("Neutral moves slowly enough that a flick of the wrist still shows")
    func aQuickTiltStillReads() {
        let tilt = CoinageTilt()
        tilt.absorb(pose(sideways(0)), after: 1.0 / 60)

        // A fifth of a second of tilting, far inside the window.
        for _ in 0 ..< 12 {
            tilt.absorb(pose(sideways(.pi / 6)), after: 1.0 / 60)
        }

        tilt.advance(by: 1)
        #expect(tilt.angles.yaw > 0.5)
    }

    @Test("Sideways reaches the ends of its travel and goes no further")
    func sidewaysIsBounded() {
        // Past the range, not at it: one reading has already nudged neutral, so a tilt of
        // exactly the range falls a hair short of the end of the travel.
        for angle in [Double(CoinageTilt.range) * 1.2, .pi / 3, .pi / 2] {
            let tilt = CoinageTilt()
            tilt.absorb(pose(sideways(0)), after: 1.0 / 60)
            tilt.absorb(pose(sideways(angle)), after: 1.0 / 60)
            tilt.advance(by: 1)

            #expect(abs(tilt.angles.yaw - CoinageTilt.travel) < 1e-6)
        }
    }

    @Test("Neutral averages bearings as directions, so the half-turn wrap is not a jump")
    func neutralHandlesTheWrap() {
        // Either side of the wrap: one just under half a turn, one just over.
        var neutral = CoinageTilt.Neutral(pose: pose(sideways(.pi - 0.05)))
        neutral.absorb(pose(sideways(-.pi + 0.05)), blend: 0.5)

        #expect(abs(abs(neutral.sideways) - .pi) < 0.06)
    }

    @Test("Flat on a table the sideways angle holds still rather than chasing noise")
    func flatKeepsItsBearing() {
        let tilt = CoinageTilt()
        tilt.absorb(pose(sideways(0)), after: 1.0 / 60)
        tilt.absorb(pose(sideways(.pi / 6)), after: 1.0 / 60)
        tilt.advance(by: 1)

        let held = tilt.angles.yaw
        tilt.absorb(pose(CMAcceleration(x: 0, y: 0, z: -1)), after: 1.0 / 60)
        tilt.advance(by: 1)

        #expect(tilt.angles.yaw == held)
    }
}

@Suite("Coin flight stagger")
struct CoinageStaggerTests {
    @Test("Leaving the strip, the first coin sets off first")
    func fromFrontLeadsWithTheFirst() {
        let stagger = CoinageCoinField.Stagger.fromFront

        #expect(stagger.position(of: 0, of: 10) == 0)
        #expect(stagger.position(of: 9, of: 10) == 9)
    }

    @Test("Spreading into the grid, the last coin sets off first")
    func fromBackLeadsWithTheLast() {
        let stagger = CoinageCoinField.Stagger.fromBack

        #expect(stagger.position(of: 9, of: 10) == 0)
        #expect(stagger.position(of: 0, of: 10) == 9)
    }

    @Test("Either way every coin takes its own place in the order")
    func everyCoinGetsOnePlace() {
        for stagger in [CoinageCoinField.Stagger.fromFront, .fromBack] {
            let places = (0 ..< 24).map { stagger.position(of: $0, of: 24) }

            #expect(Set(places) == Set(0 ..< 24))
        }
    }
}

/// The shader's parameter block is padded to its own alignment, and Metal on a device refuses a
/// buffer smaller than the struct it declares — it fails at the draw call and says nothing useful.
/// Cheaper to assert the size here than to find it on hardware.
@Suite("Coin shader parameters")
struct CoinageParamsTests {
    @Test("The parameter block is the size the shader's struct is padded to")
    func packedMatchesTheShaderStruct() throws {
        let store = try? CoinageAssetStore(device: MTLCreateSystemDefaultDevice()!)
        let packed = try #require(store?.params.packed(), "assets did not load")
        let bytes = packed.count * MemoryLayout<Float>.size

        #expect(bytes % CoinageAssetStore.Params.alignment == 0)
        // CoinParams in CoinageCoin.metal. Recheck with a static_assert in a scratch .metal file if
        // a field is added and this starts failing.
        #expect(bytes == 128)
    }
}
